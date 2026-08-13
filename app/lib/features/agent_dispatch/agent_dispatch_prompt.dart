/// 把 skill 全文作为指令；「本次调用」符合 skill 第 3 步对调用正文的约定。
String buildSkillDispatchPrompt({
  required String skillMarkdown,
  String? projectTitle,
}) {
  final skill = skillMarkdown.trim();
  final callBody = StringBuffer();
  final title = projectTitle?.trim();
  if (title != null && title.isNotEmpty) {
    callBody.writeln('name:$title');
  }

  return '''
你必须严格按下列 Skill 执行。
「Skill 正文」是完整流程；「本次调用」才是 Skill 第 3 步所说的调用正文（可为空，表示使用看板当前打开的项目）。

# Skill 正文

$skill

# 本次调用

${callBody.toString().trim().isEmpty ? '（空：使用看板当前打开的项目）' : callBody.toString().trim()}
''';
}
