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
Worker 会在本提示后继续注入完整用户 Rule、Architecture 与唯一卡片上下文；其中要求再次读取 Skill 或 Architecture 的条款视为已满足。看板工具、Git、验证和终态协议以 Skill 正文为准。

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
