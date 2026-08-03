/// 快速录入支持的卡片优先级。
enum QuickCapturePriority {
  low,
  medium,
  high,
}

/// 快速录入文本解析后的结构化草稿。
///
/// 此模型不依赖界面或看板模型，调用方可在确认录入时将字段映射到卡片。
class QuickCaptureDraft {
  const QuickCaptureDraft({
    required this.title,
    this.labels = const [],
    this.priority,
    this.columnName,
    this.dueDate,
  });

  /// 去除已识别指令后的标题；无法识别的内容会保留在这里。
  final String title;

  /// 按输入顺序排列且已去重的标签名称。
  final List<String> labels;

  /// 输入中最后一个有效的优先级。
  final QuickCapturePriority? priority;

  /// 输入中最后一个有效的目标列名。
  final String? columnName;

  /// 本地时区中的到期自然日零点。
  final DateTime? dueDate;
}
