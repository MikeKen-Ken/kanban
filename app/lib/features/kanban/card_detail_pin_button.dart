import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/board_controller.dart';

/// 卡片详情顶栏置顶按钮。
class CardDetailPinButton extends StatelessWidget {
  const CardDetailPinButton({
    super.key,
    required this.columnId,
    required this.cardId,
  });

  final String columnId;
  final String cardId;

  @override
  Widget build(BuildContext context) {
    final pinned = context.select<BoardController, bool>(
      (c) => c.isCardPinned(columnId, cardId),
    );
    final controller = context.read<BoardController>();

    return IconButton(
      tooltip: pinned ? '取消置顶' : '置顶',
      onPressed: () => controller.toggleCardPin(columnId, cardId),
      icon: Icon(
        pinned ? Icons.push_pin : Icons.push_pin_outlined,
        color: pinned ? Theme.of(context).colorScheme.primary : null,
      ),
    );
  }
}
