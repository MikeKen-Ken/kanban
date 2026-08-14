import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'card_complete_motion.dart';

/// 卡片左侧完成勾选：先播缩放回弹，再通知父级改看板。
class CardCompleteCheckbox extends StatefulWidget {
  const CardCompleteCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final Future<void> Function(bool? value) onChanged;

  @override
  State<CardCompleteCheckbox> createState() => _CardCompleteCheckboxState();
}

class _CardCompleteCheckboxState extends State<CardCompleteCheckbox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final Animation<double> _scale;
  late bool _value;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _value = widget.value;
    _scaleController = AnimationController(
      vsync: this,
      duration: CardCompleteMotion.checkbox,
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1, end: 0.86)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 36,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.86, end: 1.08)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.08, end: 1)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 24,
      ),
    ]).animate(_scaleController);
  }

  @override
  void didUpdateWidget(covariant CardCompleteCheckbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_busy && widget.value != _value) {
      _value = widget.value;
    }
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  Future<void> _handleChanged(bool? next) async {
    if (next == null || _busy) return;
    _busy = true;
    setState(() => _value = next);
    HapticFeedback.selectionClick();
    try {
      if (!MediaQuery.disableAnimationsOf(context)) {
        await _scaleController.forward(from: 0);
      }
      await widget.onChanged(next);
    } finally {
      if (mounted) {
        _busy = false;
        if (widget.value != _value) {
          setState(() => _value = widget.value);
        }
        _scaleController.reset();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Checkbox(
        key: const ValueKey('card-complete-checkbox'),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        value: _value,
        onChanged: _busy ? (_) {} : _handleChanged,
      ),
    );
  }
}
