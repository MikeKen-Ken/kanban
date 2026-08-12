import 'dart:convert';

/// 把看板 workItems 打成给 Cursor/Codex 的实施提示词。
String buildAgentDispatchPrompt({
  required String projectId,
  required String cardId,
  required String cardTitle,
  String? cardDescription,
  required Map<String, dynamic> workScope,
  required String repoPath,
}) {
  final buffer = StringBuffer()
    ..writeln('你是本机代码仓库中的实施 Agent。请直接改代码完成下列看板任务。')
    ..writeln()
    ..writeln('仓库路径：$repoPath')
    ..writeln('看板项目 id：$projectId')
    ..writeln('卡片 id：$cardId')
    ..writeln('标题：$cardTitle');
  final description = cardDescription?.trim();
  if (description != null && description.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('备注：')
      ..writeln(description);
  }
  buffer
    ..writeln()
    ..writeln('实施范围（JSON）：')
    ..writeln(const JsonEncoder.withIndent('  ').convert(workScope))
    ..writeln()
    ..writeln('要求：')
    ..writeln('1. 只做范围内未完成项；不要扩大需求。')
    ..writeln('2. 遵守仓库现有架构与编码约定。')
    ..writeln('3. 能跑的低成本检查尽量做；不要启动 GUI/模拟器。')
    ..writeln('4. 完成后用简短中文说明改了什么；若无法完成，明确写出阻塞原因。');
  return buffer.toString();
}
