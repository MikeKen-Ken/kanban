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
禁止直接执行 git commit、git revert、git reset、git checkout、git switch、git rebase 或任何会移动 HEAD 的命令。仅当本卡正文明确要求撤销某个提交且给出哈希时，才可在 ready_to_submit 中传 gitRevertCommit；Worker 会在收尾阶段受控执行。
禁止为看板工具再拉取 schema；参数以 Skill 为准，直接调用。
Worker 已注入 Architecture.md 全文，用户规则 / AGENTS.md 中的「开发前必读」已满足；禁止再读取该文件。
看板 MCP 已由 Worker 注入本卡专用工具集；禁止列出或探测看板工具，禁止调用 pick_next_card。hubMCP 始终保留；其它 MCP 仅当当前项目配置了对应 MCP 标签时由 Worker 注入，可按本卡需要使用。
本轮卡片已由 Worker 原子领取；禁止调用 pick_next_card，也不要处理其它卡片。
完成实施后必须以 ready_to_submit 收尾，显式列出本轮完成的 checklist/feedback id。
验证必须在本会话内跑通后才能声明；禁止把 verificationCommands 交给 Worker（传入会失败）。
测试失败、卡住或超时不得当作通过。无法自动验证时只传 manualVerificationReason，并写明未执行。

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
  if (!text.startsWith('---')) return text;
  final match = RegExp(r'^---\r?\n[\s\S]*?\r?\n---\r?\n?').firstMatch(text);
  return (match == null ? text : text.substring(match.end)).trim();
}
