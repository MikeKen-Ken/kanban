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

  return '''
你必须严格按下列 Skill 执行。
「Skill 正文」是完整流程；「本次调用」才是 Skill 第 3 步所说的调用正文（可为空，表示使用看板当前打开的项目）。

# Skill 正文

$skill

# 本次调用

${callBody.toString().trim().isEmpty ? '（空：使用看板当前打开的项目）' : callBody.toString().trim()}

# 调度约束（不属于调用正文）

- 本会话只处理 1 张卡片：pick_next_card 一次，完整走完 skill 后立即停止，不要再取下一张。
- 看板调度器会按需串行启动下一会话（本次运行上限：${cardLimit.label}）；不要在本会话内并行或连续处理多张卡。
- 完成后在最后一行单独输出以下标记之一：
  - 已完成一张：KANBAN_DISPATCH:CARD_DONE
  - 当前无卡可做：KANBAN_DISPATCH:NO_CARD
- 不要修改 Skill 文件本身。
''';
}
