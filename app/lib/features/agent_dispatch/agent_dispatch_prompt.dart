/// 把 Skill 与 Worker claim 后冻结的卡片上下文组装为单卡指令。
///
/// YAML frontmatter（name/description 等）只给 Cursor 技能目录用，
/// 注入会话后会触发模型再去磁盘找 SKILL.md，因此发送前剥掉。
String buildSkillDispatchPrompt({
  required String skillMarkdown,
  required String projectId,
  String? cardContext,
  String? batchArchitectureText,
}) {
  final skill = stripSkillFrontmatter(skillMarkdown);
  final id = projectId.trim();
  final context = cardContext?.trim();
  final architecture = batchArchitectureText?.trim();

  return '''
你必须严格按下列已注入的流程执行。
下面「Skill 正文」就是完整指令，不是路径、不是需要再打开的文件。
禁止搜索、glob、grep 或读取 SKILL.md / 技能目录来「确认流程」或「定位 Skill」。
禁止读取 agent-transcripts 或任何历史对话。
禁止执行 git commit、git reset、git checkout、git switch、git rebase 或任何会移动 HEAD 的命令。
禁止为已列出的看板工具再拉取 schema；参数以 Skill 为准，直接调用。
Worker 会在卡片上下文后附上已缓存的 Architecture.md；禁止重复读取。
看板 MCP 已由 Worker 注入本卡专用工具集，不得确认、探测或列出 MCP。
本轮卡片已由 Worker 原子领取；禁止调用 pick_next_card，也不要处理其它卡片。
完成实施后必须以 ready_to_submit 收尾，显式列出本轮完成的 checklist/feedback id。
禁止在会话内预跑即将交给 ready_to_submit 的 verificationCommands；由 Worker 收尾执行。
verificationCommands 必须是与本卡改动直接相关的定向测试（例如 flutter test 某个测试文件）。
禁止提交全仓库 flutter analyze、全量 flutter test、pub get、构建、安装或启动应用。
batchArchitecture 里「每个阶段至少运行 flutter analyze」只约束人类开发/CI，不得作为单卡收尾命令。

# Skill 正文

$skill

# 本次调用

projectId:$id
${context == null || context.isEmpty ? '' : '\ncardContext:\n$context'}
${architecture == null || architecture.isEmpty ? '' : '\nbatchArchitecture:\n$architecture'}
''';
}

/// 去掉 SKILL.md 开头的 YAML frontmatter，只保留正文。
String stripSkillFrontmatter(String markdown) {
  final text = markdown.trim();
  final body = text.startsWith('---')
      ? (() {
          final match =
              RegExp(r'^---\r?\n[\s\S]*?\r?\n---\r?\n?').firstMatch(text);
          return match == null ? text : text.substring(match.end).trim();
        })()
      : text;
  return body
      .split(RegExp(r'\r?\n'))
      .where((line) => !_isArchitectureReadInstruction(line))
      .join('\n')
      .trim();
}

bool _isArchitectureReadInstruction(String line) {
  if (!line.contains('docs/Architecture.md')) return false;
  return line.contains('若存在') || line.contains('修改代码前读取');
}
