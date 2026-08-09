import 'package:flutter/material.dart';

/// 在屏幕正上方展示与主题色相关的应用内提示（桌面与 Android 共用）。
///
/// 基于 [SnackBarBehavior.floating] + 大 bottom margin 顶到正上方；
/// 颜色/圆角等视觉由 [ThemeData.snackBarTheme] 统一提供。
///
/// 顶部定位必须用 [MediaQueryData.viewPadding]：Scaffold 会把 floating
/// SnackBar 锚在 `height - viewPadding.bottom`，且 [MediaQueryData.padding]
/// 可能已被 SafeArea / Scaffold body 消费为 0。
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
  // 刘海/状态栏用 viewPadding，避免 padding 被消费后算出 0
  final topGap = media.viewPadding.top + 12;
  // floating SnackBar 默认贴底，用大 bottom margin 顶到正上方
  final barHeightEstimate = action == null ? 56.0 : 64.0;
  // Scaffold 锚点已扣除底部安全区，此处同步扣除，否则会整体上移进刘海
  final bottomMargin = (media.size.height -
          media.viewPadding.bottom -
          topGap -
          barHeightEstimate)
      .clamp(72.0, 10000.0);

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
