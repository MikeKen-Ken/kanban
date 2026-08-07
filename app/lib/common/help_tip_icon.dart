import 'package:flutter/material.dart';

/// 标题旁的小问号说明：点击或长按显示 [message]。
class HelpTipIcon extends StatefulWidget {
  const HelpTipIcon({
    super.key,
    required this.message,
    this.size = 16,
  });

  /// 说明文案（Tooltip 内容）
  final String message;

  /// 图标尺寸
  final double size;

  @override
  State<HelpTipIcon> createState() => _HelpTipIconState();
}

class _HelpTipIconState extends State<HelpTipIcon> {
  final GlobalKey<TooltipState> _tooltipKey = GlobalKey<TooltipState>();

  void _showTip() {
    _tooltipKey.currentState?.ensureTooltipVisible();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Tooltip(
      key: _tooltipKey,
      message: widget.message,
      waitDuration: const Duration(milliseconds: 400),
      showDuration: const Duration(seconds: 5),
      // 由点击/长按显式触发，避免常驻文案
      triggerMode: TooltipTriggerMode.manual,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _showTip,
          onLongPress: _showTip,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(
              Icons.help_outline,
              size: widget.size,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}
