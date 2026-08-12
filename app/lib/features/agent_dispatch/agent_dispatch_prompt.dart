import 'agent_dispatch_config.dart';

/// 把 skill 全文作为指令；「本次调用」符合 skill 第 3 步对调用正文的约定。
String buildSkillDispatchPrompt({
  required String skillMarkdown,
  String? projectTitle,
  required AgentDispatchCardLimit cardLimit,
}) {
  final skill = skillMarkdown.trim();
  final callBody = StringBuffer();
  final title = projectTitle?.trim();
  if (title != null && title.isNotEmpty) {
    callBody.writeln('name:$title');
  }

  final limitLine = switch (cardLimit) {
    AgentDispatchCardLimitMax() =>
      '卡片上限：不限（按 skill 连续处理，直到 pick_next_card 返回 found=false）。',
    AgentDispatchCardLimitCount(:final count) =>
      '卡片上限：最多 $count 张（每张完整走完 skill 后再取下一张；达上限或无卡则停止）。',
  };

  return '''
你必须严格按下列 Skill 执行。
「Skill 正文」是完整流程；「本次调用」才是 Skill 第 3 步所说的调用正文（可为空，表示使用看板当前打开的项目）。

# Skill 正文

$skill

# 本次调用

${callBody.toString().trim().isEmpty ? '（空：使用看板当前打开的项目）' : callBody.toString().trim()}

# 调度约束（不属于调用正文）

- $limitLine
- 不要修改 Skill 文件本身。
''';
}
