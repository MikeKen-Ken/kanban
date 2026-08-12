import 'dart:io';

import 'agent_dispatch_config.dart';
import 'agent_dispatch_prompt.dart';
import 'agent_dispatch_settings.dart';
import 'agent_dispatch_worker.dart';

/// 启动一次新的 Agent 会话：注入 skill + 本次调用，不在此层取卡/送验。
class AgentDispatchService {
  AgentDispatchService();

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
    onLog?.call('上限：${options.cardLimit.label}');
    onLog?.call('启动新会话（${options.engine.label}）…');

    final result = await runAgentWorkerJob(
      engine: options.engine,
      cwd: repo,
      prompt: prompt,
      model: options.modelId,
      modelParams: options.modelParams,
      workerScriptPath: workerScriptPath,
      onLog: (line) {
        if (_cancelRequested) return;
        onLog?.call(line);
      },
    );
    if (_cancelRequested) {
      return const AgentWorkerResult(ok: false, error: '已取消');
    }
    return result;
  }
}

/// 解析默认 skill 路径是否可读（供面板展示）。
Future<String?> peekSkillPreview(String path, {int maxChars = 1200}) async {
  final file = File(path);
  if (!await file.exists()) return null;
  final text = await file.readAsString();
  if (text.length <= maxChars) return text;
  return '${text.substring(0, maxChars)}\n…';
}

String resolveDispatchSkillPath(AgentDispatchSettings settings) =>
    settings.resolveSkillPath();
