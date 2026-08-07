import 'package:flutter/material.dart';

/// 在屏幕正上方展示与主题色相关的应用内提示（桌面与 Android 共用）。
///
/// 基于 [SnackBarBehavior.floating] + 大 bottom margin 顶到正上方；
/// 颜色/圆角等视觉由 [ThemeData.snackBarTheme] 统一提供。
void showAppSnackBar(
  BuildContext context, {
  required String message,
  SnackBarAction? action,
  Duration duration = const Duration(seconds: 4),
  bool clearExisting = false,
}) {
  final messenger = ScaffoldMessenger.of(context);
  if (clearExisting) {
    messenger.clearSnackBars();
  }

  final media = MediaQuery.of(context);
  final topGap = media.padding.top + 12;
  // floating SnackBar 默认贴底，用大 bottom margin 顶到正上方
  final barHeightEstimate = action == null ? 56.0 : 64.0;
  final bottomMargin =
      (media.size.height - topGap - barHeightEstimate).clamp(72.0, 10000.0);

  // 宽屏两侧留白，避免又长又满的一条
  final horizontal = media.size.width > 560
      ? ((media.size.width - 480) / 2).clamp(16.0, 10000.0)
      : 16.0;

  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      action: action,
      duration: duration,
      behavior: SnackBarBehavior.floating,
      dismissDirection: DismissDirection.up,
      margin: EdgeInsets.fromLTRB(horizontal, 0, horizontal, bottomMargin),
    ),
  );
}
