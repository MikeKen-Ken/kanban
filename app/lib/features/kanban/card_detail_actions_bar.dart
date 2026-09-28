import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../controllers/board_controller.dart';
import 'card_complete_motion.dart';
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
  final Future<void> Function() onComplete;
  final VoidCallback onSave;

  /// Below this width the desktop action row clips Delete against Save.
  static const _narrowLayoutWidth = 600.0;

  List<Widget> _secondaryActions(BuildContext context, ThemeData theme) {
    return [
      TextButton.icon(
        onPressed: onSaveAsTemplate,
        icon: const Icon(Icons.bookmark_add_outlined),
        label: const Text('Save as template'),
      ),
      Builder(
        builder: (context) {
          final canTransfer =
              context.watch<BoardController>().projects.length > 1;
          // 全平台可用（含 Android）；板面另有右键/「⋯」/长按入口
          return TextButton(
            onPressed: onTransfer,
            child: Text(
              'Move to…',
              style: TextStyle(
                color: canTransfer ? null : Theme.of(context).disabledColor,
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
            confirmBeforeDelete: controller.appSettings.confirmBeforeDeleteCard,
          );
          if (ok && context.mounted) {
            await controller.deleteCard(columnId, cardId);
            if (context.mounted) onDeleted();
          }
        },
        child: Text(
          'Delete',
          style: TextStyle(color: theme.colorScheme.error),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = _secondaryActions(context, theme);
    final save = FilledButton(
      onPressed: onSave,
      child: const Text('Save'),
    );
    final complete = CardDetailCompleteButton(onComplete: onComplete);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < _narrowLayoutWidth) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ...secondary,
                      if (showComplete) complete,
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                save,
              ],
            );
          }
          return Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: secondary),
                ),
              ),
              if (showComplete) ...[
                const SizedBox(width: 8),
                complete,
                const SizedBox(width: 8),
              ],
              save,
            ],
          );
        },
      ),
    );
  }
}

/// 详情「完成」：先回弹并切到已完成态，再执行真正的完成逻辑。
class CardDetailCompleteButton extends StatefulWidget {
  const CardDetailCompleteButton({
    super.key,
    required this.onComplete,
  });

  final Future<void> Function() onComplete;

  @override
  State<CardDetailCompleteButton> createState() =>
      _CardDetailCompleteButtonState();
}

class _CardDetailCompleteButtonState extends State<CardDetailCompleteButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  bool _busy = false;
  bool _succeededVisual = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: CardCompleteMotion.button,
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1, end: 0.92)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.92, end: 1)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 60,
      ),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handlePress() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _succeededVisual = true;
    });
    HapticFeedback.selectionClick();
    if (!MediaQuery.disableAnimationsOf(context)) {
      await _controller.forward(from: 0);
    }
    await widget.onComplete();
    if (!mounted) return;
    _controller.reset();
    setState(() {
      _busy = false;
      _succeededVisual = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: FilledButton.icon(
        key: const ValueKey('card-detail-complete'),
        onPressed: _busy ? () {} : _handlePress,
        icon: Icon(
          _succeededVisual ? Icons.check_circle : Icons.check,
          size: 18,
        ),
        label: AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          child: Text(
            _succeededVisual ? 'Completed' : 'Complete',
            key: ValueKey(_succeededVisual),
          ),
        ),
      ),
    );
  }
}
