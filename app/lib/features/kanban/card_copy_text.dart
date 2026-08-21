import '../../models/kanban_models.dart';

/// 把卡片主要文字内容格式化为可粘贴文本。
///
/// 包含标题、备注、子任务、验证反馈与提交号；不含附件与其它元数据。
String formatCardCopyText(KanbanCard card) {
  final buffer = StringBuffer();
  buffer.writeln(card.title);

  final description = card.description?.trim();
  if (description != null && description.isNotEmpty) {
    buffer.writeln();
    buffer.writeln('Description');
    buffer.writeln(description);
  }

  if (card.checklist.isNotEmpty) {
    buffer.writeln();
    buffer.writeln('Subtasks');
    for (final item in card.checklist) {
      buffer.writeln(_checklistLine(item));
    }
  }

  if (card.verificationFeedback.isNotEmpty) {
    buffer.writeln();
    buffer.writeln('Verification feedback');
    for (final item in card.verificationFeedback) {
      buffer.writeln(_checklistLine(item));
    }
  }

  final commitRef = card.commitRef?.trim();
  if (commitRef != null && commitRef.isNotEmpty) {
    buffer.writeln();
    buffer.writeln('Commit');
    buffer.writeln(commitRef);
  }

  return buffer.toString().trimRight();
}

String _checklistLine(ChecklistItem item) {
  final mark = item.completed ? 'x' : ' ';
  return '- [$mark] ${item.text}';
}
