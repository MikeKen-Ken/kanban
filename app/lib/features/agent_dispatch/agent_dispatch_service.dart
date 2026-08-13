import 'dart:io';

import 'agent_dispatch_config.dart';
import 'agent_dispatch_credentials.dart';
import 'agent_dispatch_prompt.dart';
import 'agent_dispatch_session.dart';
import 'agent_dispatch_settings.dart';
import 'agent_dispatch_worker.dart';

/// 启动一次新的 Agent 会话：注入 skill + 本次调用，不在此层取卡/送验。
class AgentDispatchService {
  AgentDispatchService({
    AgentDispatchCredentials credentials = const AgentDispatchCredentials(),
  }) : _credentials = credentials;

  final AgentDispatchCredentials _credentials;

  bool _cancelRequested = false;

  void requestCancel() => _cancelRequested = true;

  Future<AgentWorkerResult> runOnce({
    required AgentDispatchRunOptions options,
    required String skillPath,
    String? workerScriptPath,
    void Function(String line)? onLog,
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
    final prompt = buildSkillDispatchPrompt(
      skillMarkdown: skillMarkdown,
      projectTitle: options.projectTitle,
      cardLimit: options.cardLimit,
    );

    onLog?.call(
      'Skill：${options.projectTitle ?? '当前项目'}',
    );
    onLog?.call('仓库：$repo');
    onLog?.call('上限：${options.cardLimit.label}（逐张串行启动会话）');

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

    final sessionLimit = dispatchSessionLimit(options.cardLimit);
    AgentWorkerResult last = const AgentWorkerResult(
      ok: false,
      error: '未启动会话',
    );
    for (var index = 1; index <= sessionLimit; index++) {
      if (_cancelRequested) {
        return const AgentWorkerResult(ok: false, error: '已取消');
      }
      onLog?.call(
        '启动新会话（${options.engine.label}）第 $index 张…',
      );
      final sessionLog = StringBuffer();
      last = await runAgentWorkerJob(
        engine: options.engine,
        cwd: repo,
        prompt: prompt,
        model: options.modelId,
        modelParams: options.modelParams,
        cursorApiKey: cursorApiKey,
        workerScriptPath: workerScriptPath,
        onLog: (line) {
          sessionLog.writeln(line);
          if (_cancelRequested) return;
          onLog?.call(line);
        },
      );
      if (_cancelRequested) {
        return const AgentWorkerResult(ok: false, error: '已取消');
      }
      if (!shouldContinueDispatch(
        cardLimit: options.cardLimit,
        finishedSessions: index,
        lastResult: last,
        sessionLog: sessionLog.toString(),
        cancelRequested: _cancelRequested,
      )) {
        if (dispatchSessionHasNoCard(
          result: last,
          sessionLog: sessionLog.toString(),
        )) {
          onLog?.call('无更多卡片，结束调度');
          if (index == 1 && last.ok) {
            return last;
          }
          return AgentWorkerResult(
            ok: last.ok,
            summary: last.summary ?? '已处理 ${index - 1} 张后无更多卡片',
            error: last.error,
            exitCode: last.exitCode,
          );
        }
        return last;
      }
      onLog?.call('第 $index 张完成，准备下一张…');
    }
    return last;
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
