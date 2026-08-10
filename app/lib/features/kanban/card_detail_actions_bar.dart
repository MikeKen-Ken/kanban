import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/board_controller.dart';
import 'confirm_delete_card.dart';

/// 卡片详情底栏：模板、转移、删除、完成、保存。
class CardDetailActionsBar extends StatelessWidget {
  const CardDetailActionsBar({
    super.key,
    required this.columnId,
    required this.cardId,
    required this.cardTitle,
    required this.showComplete,
    required this.onSaveAsTemplate,
    required this.onTransfer,
    required this.onDeleted,
    required this.onComplete,
    required this.onSave,
  });

  final String columnId;
  final String cardId;
  final String cardTitle;
  final bool showComplete;
  final VoidCallback onSaveAsTemplate;
  final VoidCallback onTransfer;
  final VoidCallback onDeleted;
  final VoidCallback onComplete;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: onSaveAsTemplate,
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: const Text('存为模板'),
                  ),
                  Builder(
                    builder: (context) {
                      final canTransfer =
                          context.watch<BoardController>().projects.length > 1;
                      // 全平台可用（含 Android）；板面另有右键/「⋯」/长按入口
                      return TextButton(
                        onPressed: onTransfer,
                        child: Text(
                          '转移到…',
                          style: TextStyle(
                            color: canTransfer
                                ? null
                                : Theme.of(context).disabledColor,
                          ),
                        ),
                      );
                    },
                  ),
                  TextButton(
                    onPressed: () async {
                      final controller = context.read<BoardController>();
                      final ok = await confirmDeleteCardIfNeeded(
                        context: context,
                        cardTitle: cardTitle,
                        confirmBeforeDelete:
                            controller.appSettings.confirmBeforeDeleteCard,
                      );
                      if (ok && context.mounted) {
                        await controller.deleteCard(columnId, cardId);
                        if (context.mounted) onDeleted();
                      }
                    },
                    child: Text(
                      '删除',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (showComplete) ...[
            const SizedBox(width: 8),
            FilledButton.icon(
              key: const ValueKey('card-detail-complete'),
              onPressed: onComplete,
              icon: const Icon(Icons.check, size: 18),
              label: const Text('完成'),
            ),
            const SizedBox(width: 8),
          ],
          FilledButton(
            onPressed: onSave,
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
