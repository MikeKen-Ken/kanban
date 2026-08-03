import 'quick_capture_draft.dart';

final RegExp _whitespace = RegExp(r'\s+');

/// 将一行快速录入文本解析为结构化草稿。
///
/// 指令必须是由空白分隔的完整片段。无法识别或缺少内容的片段不会丢失，
/// 而是按原顺序保留在标题中。
QuickCaptureDraft parseQuickCapture(
  String input, {
  DateTime? now,
}) {
  final titleParts = <String>[];
  final labels = <String>[];
  final seenLabels = <String>{};
  QuickCapturePriority? priority;
  String? columnName;
  DateTime? dueDate;

  final trimmedInput = input.trim();
  if (trimmedInput.isEmpty) {
    return const QuickCaptureDraft(title: '');
  }

  final localToday = _localNaturalDay(now ?? DateTime.now());
  for (final part in trimmedInput.split(_whitespace)) {
    final label = _valueAfterPrefix(part, '#');
    if (label != null) {
      if (seenLabels.add(label)) {
        labels.add(label);
      }
      continue;
    }

    final parsedPriority = _parsePriority(part);
    if (parsedPriority != null) {
      priority = parsedPriority;
      continue;
    }

    final column = _valueAfterPrefix(part, '@');
    if (column != null) {
      columnName = column;
      continue;
    }

    final dayOffset = _parseDayOffset(part);
    if (dayOffset != null) {
      dueDate = localToday.add(Duration(days: dayOffset));
      continue;
    }

    titleParts.add(part);
  }

  return QuickCaptureDraft(
    title: titleParts.join(' '),
    labels: List.unmodifiable(labels),
    priority: priority,
    columnName: columnName,
    dueDate: dueDate,
  );
}

String? _valueAfterPrefix(String part, String prefix) {
  if (!part.startsWith(prefix) || part.length == prefix.length) {
    return null;
  }
  return part.substring(prefix.length);
}

QuickCapturePriority? _parsePriority(String part) {
  return switch (part) {
    '!低' => QuickCapturePriority.low,
    '!中' => QuickCapturePriority.medium,
    '!高' => QuickCapturePriority.high,
    _ => null,
  };
}

int? _parseDayOffset(String part) {
  return switch (part) {
    '今天' => 0,
    '明天' => 1,
    '后天' => 2,
    '下周' => 7,
    _ => null,
  };
}

DateTime _localNaturalDay(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}
