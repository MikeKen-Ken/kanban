import 'package:flutter/material.dart';

OverlayEntry? _activeAppSnackBarEntry;

/// 在屏幕正上方展示与主题色相关的应用内提示（桌面与 Android 共用）。
///
/// 通过 [Overlay] 顶部对齐展示，避免 [SnackBar] 用大 bottom margin 贴顶时
/// 高度估算不准或退场动画留下可见小块。
/// 颜色/圆角等视觉由 [ThemeData.snackBarTheme] 统一提供。
void showAppSnackBar(
  BuildContext context, {
  required String message,
  SnackBarAction? action,
  Duration duration = const Duration(seconds: 4),
  bool clearExisting = false,
}) {
  if (message.trim().isEmpty) return;

  if (clearExisting) {
    ScaffoldMessenger.of(context).clearSnackBars();
  }

  _removeActiveAppSnackBar();

  final overlay = Overlay.of(context);
  late OverlayEntry entry;

  void onDismissed() {
    entry.remove();
    if (_activeAppSnackBarEntry == entry) {
      _activeAppSnackBarEntry = null;
    }
  }

  entry = OverlayEntry(
    builder: (overlayContext) => _AppTopSnackBar(
      message: message,
      action: action,
      duration: duration,
      onDismissed: onDismissed,
    ),
  );

  _activeAppSnackBarEntry = entry;
  overlay.insert(entry);
}

void _removeActiveAppSnackBar() {
  _activeAppSnackBarEntry?.remove();
  _activeAppSnackBarEntry = null;
}

class _AppTopSnackBar extends StatefulWidget {
  const _AppTopSnackBar({
    required this.message,
    required this.duration,
    required this.onDismissed,
    this.action,
  });

  final String message;
  final SnackBarAction? action;
  final Duration duration;
  final VoidCallback onDismissed;

  @override
  State<_AppTopSnackBar> createState() => _AppTopSnackBarState();
}

class _AppTopSnackBarState extends State<_AppTopSnackBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      reverseDuration: const Duration(milliseconds: 200),
    );
    final curve = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(curve);
    _fade = curve;
    _controller.forward();
    Future<void>.delayed(widget.duration, _dismiss);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (_dismissing || !mounted) return;
    _dismissing = true;
    await _controller.reverse();
    if (mounted) {
      widget.onDismissed();
    }
  }

  void _onActionPressed() {
    widget.action?.onPressed();
    _dismiss();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snackBarTheme = theme.snackBarTheme;
    final colorScheme = theme.colorScheme;
    final media = MediaQuery.of(context);

    final backgroundColor =
        snackBarTheme.backgroundColor ?? colorScheme.primaryContainer;
    final contentStyle = snackBarTheme.contentTextStyle ??
        TextStyle(color: colorScheme.onPrimaryContainer, fontSize: 14);
    final actionColor =
        widget.action?.textColor ??
        snackBarTheme.actionTextColor ??
        colorScheme.primary;
    final shape = snackBarTheme.shape ??
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    final elevation = snackBarTheme.elevation ?? 3;
    // SnackBarThemeData 无 contentPadding；与 SnackBar floating 默认内边距对齐
    const contentPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 14);

    // 宽屏两侧留白，避免又长又满的一条
    final horizontal = media.size.width > 560
        ? ((media.size.width - 480) / 2).clamp(16.0, double.infinity)
        : 16.0;

    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(horizontal, 12, horizontal, 0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SlideTransition(
              position: _slide,
              child: FadeTransition(
                opacity: _fade,
                child: Material(
                  elevation: elevation,
                  color: backgroundColor,
                  shape: shape,
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: contentPadding,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(widget.message, style: contentStyle),
                        ),
                        if (widget.action != null) ...[
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: _onActionPressed,
                            style: TextButton.styleFrom(
                              foregroundColor: actionColor,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(widget.action!.label),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
