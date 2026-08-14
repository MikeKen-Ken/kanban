/// 把 skill 全文作为指令；「本次调用」只给出项目 UUID。
String buildSkillDispatchPrompt({
  required String skillMarkdown,
  required String projectId,
}) {
  final skill = skillMarkdown.trim();
  final id = projectId.trim();

  return '''
你必须严格按下列 Skill 执行。
「Skill 正文」是完整流程；「本次调用」只提供 projectId（项目 UUID）。
取卡时必须把该 UUID 传给 pick_next_card 的 projectId；不要用项目名，不要省略，不要改用界面当前打开的其它项目。

# Skill 正文

$skill

# 本次调用

projectId:$id
''';
}
