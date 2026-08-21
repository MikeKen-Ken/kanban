import 'package:flutter/material.dart';

import '../../controllers/board_controller.dart';
import '../../models/kanban_models.dart';

/// 同步冲突提示条：展示冲突摘要与「保留当前 / 保留另一份」操作。
class CardDetailConflictBanner extends StatelessWidget {
  const CardDetailConflictBanner({
    super.key,
    required this.card,
    required this.resolving,
    required this.onResolve,
  });

  final KanbanCard card;
  final bool resolving;
  final ValueChanged<CardConflictResolution> onResolve;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              card.conflictDeleted
                  ? 'Sync conflict: this card was deleted on the other side'
                  : 'Sync conflict: another copy exists',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (card.conflictSide != null) ...[
              const SizedBox(height: 6),
              Text(
                'Other copy: ${card.conflictSide!.title}'
                '${card.conflictSide!.description == null || card.conflictSide!.description!.isEmpty ? '' : ' — ${card.conflictSide!.description}'}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: resolving
                      ? null
                      : () => onResolve(CardConflictResolution.keepPrimary),
                  child: Text(resolving ? 'Processing…' : 'Keep current'),
                ),
                OutlinedButton(
                  onPressed: resolving
                      ? null
                      : () => onResolve(CardConflictResolution.keepOther),
                  child: Text(
                    resolving
                        ? 'Processing…'
                        : (card.conflictDeleted
                            ? 'Confirm delete'
                            : 'Keep other'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
