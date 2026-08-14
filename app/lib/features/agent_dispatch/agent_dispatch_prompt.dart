/// 把 skill 全文作为指令；「本次调用」符合 skill 第 3 步对调用正文的约定。
String buildSkillDispatchPrompt({
  required String skillMarkdown,
  required String projectTitle,
  required String projectId,
}) {
  final skill = skillMarkdown.trim();
  final title = projectTitle.trim();
  final id = projectId.trim();
  final callBody = StringBuffer()
    ..writeln('name:${title.isEmpty ? id : title}')
    ..writeln('projectId:$id');

  return '''
你必须严格按下列 Skill 执行。
「Skill 正文」是完整流程；「本次调用」才是 Skill 第 3 步所说的调用正文。
所有看板 MCP 工具调用都必须传入本次的 projectId，不要改用界面当前打开的其它项目。

# Skill 正文

$skill

# 本次调用

${callBody.toString().trim()}
''';
}
