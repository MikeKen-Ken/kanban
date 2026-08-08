import '../kanban/kanban_labels.dart';
import '../../models/kanban_models.dart';

/// 看板泳道分组方式（随项目设置同步）。
enum SwimlaneMode {
  none,
  priority,
  label,
}

extension SwimlaneModeX on SwimlaneMode {
  String get label => switch (this) {
        SwimlaneMode.none => '关闭',
        SwimlaneMode.priority => '按优先级',
        SwimlaneMode.label => '按标签',
      };

  static SwimlaneMode fromString(String? value) {
    return SwimlaneMode.values.firstWhere(
      (item) => item.name == value,
      orElse: () => SwimlaneMode.none,
    );
  }
}

/// 顶栏按钮每次点击后的泳道顺序。
SwimlaneMode nextSwimlaneMode(SwimlaneMode current) {
  return switch (current) {
    SwimlaneMode.none => SwimlaneMode.priority,
    SwimlaneMode.priority => SwimlaneMode.label,
    SwimlaneMode.label => SwimlaneMode.none,
  };
}

/// 一条泳道的标识与展示。
class SwimlaneBucket {
  const SwimlaneBucket({
    required this.id,
    required this.title,
    this.priority,
    this.labelKey,
  });

  final String id;
  final String title;
  final CardPriority? priority;
  final String? labelKey;
}

/// 按泳道模式拆分卡片。
class SwimlaneService {
  const SwimlaneService();

  List<SwimlaneBucket> bucketsFor({
    required SwimlaneMode mode,
    required Iterable<KanbanCard> cards,
    List<KanbanLabel> customLabels = const [],
    String themeId = '',
  }) {
    switch (mode) {
      case SwimlaneMode.none:
        return const [SwimlaneBucket(id: 'all', title: '全部')];
      case SwimlaneMode.priority:
        return [
          for (final priority in [
            CardPriority.high,
            CardPriority.medium,
            CardPriority.low,
            CardPriority.none,
          ])
            SwimlaneBucket(
              id: 'priority:${priority.name}',
              title: '优先级 · ${priority.label}',
              priority: priority,
            ),
        ];
      case SwimlaneMode.label:
        final keys = <String>{};
        for (final card in cards) {
          keys.addAll(card.labels);
        }
        final sorted = keys.toList()
          ..sort((a, b) {
            final an = findKanbanLabel(a, customLabels, themeId)?.name ?? a;
            final bn = findKanbanLabel(b, customLabels, themeId)?.name ?? b;
            return an.compareTo(bn);
          });
        return [
          for (final key in sorted)
            SwimlaneBucket(
              id: 'label:$key',
              title: findKanbanLabel(key, customLabels, themeId)?.name ?? key,
              labelKey: key,
            ),
          const SwimlaneBucket(
            id: 'label:',
            title: '无标签',
            labelKey: '',
          ),
        ];
    }
  }

  bool cardMatches(KanbanCard card, SwimlaneBucket bucket, SwimlaneMode mode) {
    switch (mode) {
      case SwimlaneMode.none:
        return true;
      case SwimlaneMode.priority:
        return card.priority == bucket.priority;
      case SwimlaneMode.label:
        final key = bucket.labelKey;
        if (key == null) return true;
        if (key.isEmpty) return card.labels.isEmpty;
        return card.labels.contains(key);
    }
  }

  /// 将卡片拖入某泳道时应写入的字段变更。
  KanbanCard applyBucket(KanbanCard card, SwimlaneBucket bucket, SwimlaneMode mode) {
    switch (mode) {
      case SwimlaneMode.none:
        return card;
      case SwimlaneMode.priority:
        final priority = bucket.priority ?? CardPriority.none;
        return card.copyWith(priority: priority);
      case SwimlaneMode.label:
        final key = bucket.labelKey;
        if (key == null) return card;
        if (key.isEmpty) {
          return card.copyWith(labels: const []);
        }
        if (card.labels.contains(key)) return card;
        return card.copyWith(labels: [...card.labels, key]);
    }
  }
}
