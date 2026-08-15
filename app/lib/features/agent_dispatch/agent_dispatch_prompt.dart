/// 把 skill 正文作为指令；「本次调用」只给出项目 UUID。
///
/// YAML frontmatter（name/description 等）只给 Cursor 技能目录用，
/// 注入会话后会触发模型再去磁盘找 SKILL.md，因此发送前剥掉。
String buildSkillDispatchPrompt({
  required String skillMarkdown,
  required String projectId,
}) {
  final skill = stripSkillFrontmatter(skillMarkdown);
  final id = projectId.trim();

  return '''
你必须严格按下列已注入的流程执行。
下面「Skill 正文」就是完整指令，不是路径、不是需要再打开的文件。
禁止搜索、glob、grep 或读取 SKILL.md / 技能目录来「确认流程」或「定位 Skill」。
禁止读取 agent-transcripts 或任何历史对话。
禁止任何 git 命令；提交与送验只调用 commit_and_submit_card。
禁止为已列出的看板工具再拉取 schema；参数以 Skill 为准，直接调用。
Architecture.md 若存在则直接 Read 该路径，禁止 glob 探测。
看板 MCP 已由 Worker 注入精简工具集，无需探测或列出全部工具。
「本次调用」只提供 projectId（项目 UUID）。
取卡时必须把该 UUID 传给 pick_next_card 的 projectId；不要用项目名，不要省略，不要改用界面当前打开的其它项目。

# Skill 正文

$skill

# 本次调用

projectId:$id
''';
}

/// 去掉 SKILL.md 开头的 YAML frontmatter，只保留正文。
String stripSkillFrontmatter(String markdown) {
  final text = markdown.trim();
  if (!text.startsWith('---')) return text;
  final match = RegExp(r'^---\r?\n[\s\S]*?\r?\n---\r?\n?').firstMatch(text);
  if (match == null) return text;
  return text.substring(match.end).trim();
}
