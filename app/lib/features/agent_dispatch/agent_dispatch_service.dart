import 'dart:async';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../mcp/mcp_dispatch_card_gate.dart';
import 'agent_dispatch_config.dart';
import 'agent_dispatch_credentials.dart';
import 'agent_dispatch_log.dart';
import 'agent_dispatch_prompt.dart';
import 'agent_dispatch_settings.dart';
import 'agent_dispatch_worker.dart';

/// 启动一次 Worker 批次；Worker 只调度，每轮 Agent 按 Skill 自己取一张卡。
class AgentDispatchService {
  AgentDispatchService({
    AgentDispatchCredentials credentials = const AgentDispatchCredentials(),
  }) : _credentials = credentials {
    _liveServices.add(this);
  }

  static final Set<AgentDispatchService> _liveServices = {};

  final AgentDispatchCredentials _credentials;

  bool _cancelRequested = false;
  AgentWorkerProcess? _activeWorker;

  /// 立即停止当前 Worker 及其 SDK/CLI 子进程，并阻止后续会话启动。
  Future<void> requestCancel() async {
    _cancelRequested = true;
    final worker = _activeWorker;
    if (worker != null) await worker.stop();
  }

  /// 应用退出时停止所有由 Agent 工作台创建的 Worker。
  ///
  /// 逐个 Worker 使用 `taskkill /T`，以确保 SDK/CLI 子进程不会遗留。
  static Future<void> stopAllForAppExit() async {
    final services = _liveServices.toList(growable: false);
    await Future.wait(services.map((service) => service.requestCancel()));
  }

  /// 面板销毁后不再参与应用级退出清理；若仍在运行则同时终止。
  Future<void> dispose() async {
    _liveServices.remove(this);
    await requestCancel();
  }

  Future<AgentWorkerResult> runOnce({
    required AgentDispatchRunOptions options,
    required String skillPath,
    required String mcpEndpoint,
    String? workerScriptPath,
    void Function(AgentDispatchLogEntry entry)? onLog,
  }) async {
    _cancelRequested = false;
    final repo = options.repoPath.trim();
    if (repo.isEmpty) {
      return const AgentWorkerResult(ok: false, error: '请填写代码仓库路径');
    }
    if (!await Directory(repo).exists()) {
      return AgentWorkerResult(ok: false, error: '仓库路径不存在：$repo');
    }

    final skillFile = File(skillPath);
    if (!await skillFile.exists()) {
      return AgentWorkerResult(
        ok: false,
        error: '未找到 Skill：$skillPath',
      );
    }
    final skillMarkdown = await skillFile.readAsString();
    void log(
      String message, {
      AgentDispatchLogLevel level = AgentDispatchLogLevel.info,
    }) {
      onLog?.call(AgentDispatchLogEntry(message, level: level));
    }

    log('项目：${options.projectTitle ?? '看板当前项目'}');
    log('仓库：$repo');
    log('策略：每张卡片创建一次独立 Agent 调用；上限 ${options.cardLimit.label}');

    String? cursorApiKey;
    if (options.engine == AgentDispatchEngine.cursor) {
      try {
        cursorApiKey = await _credentials.resolveCursorApiKey();
      } catch (error) {
        return AgentWorkerResult(
          ok: false,
          error: '读取 Cursor API Key 的系统安全存储失败：$error',
        );
      }
    }
    if (options.engine == AgentDispatchEngine.cursor && cursorApiKey == null) {
      return const AgentWorkerResult(
        ok: false,
        error: '尚未配置 Cursor API Key，请先在 Agent 调度面板中安全保存',
      );
    }

    final runId = const Uuid().v4();
    final workerToken = const Uuid().v4();
    final cardLimit = switch (options.cardLimit) {
      AgentDispatchCardLimitMax() => 999,
      AgentDispatchCardLimitCount(:final count) => count,
    };
    final prompt = buildSkillDispatchPrompt(
      skillMarkdown: skillMarkdown,
      projectTitle: options.projectTitle,
    );
    log('批次 id：$runId');
    log('Worker 只读检查队列；每轮由全新 Skill 会话自己领取并处理一张卡');
    final stopwatch = Stopwatch()..start();
    late AgentWorkerResult result;
    McpDispatchCardGate.instance.beginBatch(workerToken);
    try {
      result = await runAgentWorkerJob(
        engine: options.engine,
        cwd: repo,
        prompt: prompt,
        mcpEndpoint: mcpEndpoint,
        projectId: options.projectId,
        cardLimit: cardLimit,
        workerToken: workerToken,
        model: options.modelId,
        modelParams: options.modelParams,
        cursorApiKey: cursorApiKey,
        workerScriptPath: workerScriptPath,
        onProcessStarted: (worker) {
          _activeWorker = worker;
          if (_cancelRequested) unawaited(worker.stop());
        },
        onLog: (line) {
          if (_cancelRequested) return;
          final normalized = line.trimLeft();
          final level = switch (normalized) {
            final value when value.startsWith('[success]') =>
              AgentDispatchLogLevel.success,
            final value when value.startsWith('[warning]') =>
              AgentDispatchLogLevel.warning,
            final value when value.startsWith('[error]') =>
              AgentDispatchLogLevel.error,
            final value when value.startsWith('[err]') =>
              AgentDispatchLogLevel.warning,
            _ => AgentDispatchLogLevel.info,
          };
          final message = normalized.replaceFirst(
            RegExp(r'^\[(success|warning|error)\]\s*'),
            '',
          );
          log(
            message,
            level: level,
          );
        },
      );
    } catch (error) {
      result = AgentWorkerResult(ok: false, error: 'Worker 启动或通信失败：$error');
    } finally {
      McpDispatchCardGate.instance.endBatch(workerToken);
      _activeWorker = null;
      stopwatch.stop();
    }
    if (_cancelRequested) {
      log('Worker 批次已由用户终止', level: AgentDispatchLogLevel.warning);
      return const AgentWorkerResult(ok: false, error: '已取消');
    }
    log(
      'Worker 退出：exitCode=${result.exitCode ?? '未知'}，'
      '已处理 ${result.processedCards ?? 0} 张，耗时 ${stopwatch.elapsed.inSeconds} 秒',
      level: result.ok
          ? AgentDispatchLogLevel.success
          : AgentDispatchLogLevel.error,
    );
    if (!result.ok) {
      log(result.error ?? 'Worker 批次失败', level: AgentDispatchLogLevel.error);
    }
    return result;
  }
}

/// 解析默认 skill 路径是否可读（供面板展示）。
Future<String?> peekSkillPreview(String path) async {
  final file = File(path);
  if (!await file.exists()) return null;
  return file.readAsString();
}

String resolveDispatchSkillPath(AgentDispatchSettings settings) =>
    settings.resolveSkillPath();
