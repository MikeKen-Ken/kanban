import 'package:flutter/material.dart';

/// 删除按钮在紧凑密度下约占的宽度。
const kAdaptivePopupMenuDeleteButtonWidth = 40.0;

/// Key 菜单：勾选列 + 间距 + 删除按钮。
const kAdaptivePopupMenuKeyTrailingWidth =
    18.0 + 8.0 + kAdaptivePopupMenuDeleteButtonWidth;

/// [PopupMenuItem] 默认左右各 16。
const kAdaptivePopupMenuItemPadding = 32.0;

const _minMenuWidth = 96.0;
const _maxMenuWidth = 720.0;

/// 按最长文案测算弹出菜单宽度：短名收窄，长名拉宽，不超过屏宽。
double adaptivePopupMenuWidth({
  required BuildContext context,
  required Iterable<String> labels,
  required double trailingWidth,
  double minWidth = _minMenuWidth,
  double maxWidth = _maxMenuWidth,
}) {
  final textTheme = Theme.of(context).textTheme;
  final style = textTheme.titleMedium ??
      textTheme.bodyLarge ??
      const TextStyle(fontSize: 16);
  final scaler = MediaQuery.textScalerOf(context);
  final direction = Directionality.of(context);
  var maxTextWidth = 0.0;
  for (final label in labels) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      maxLines: 1,
      textDirection: direction,
      textScaler: scaler,
    )..layout();
    if (painter.width > maxTextWidth) {
      maxTextWidth = painter.width;
    }
  }
  final desired =
      maxTextWidth + trailingWidth + kAdaptivePopupMenuItemPadding;
  final screenCap = MediaQuery.sizeOf(context).width * 0.92;
  final cap = maxWidth < screenCap ? maxWidth : screenCap;
  return desired.clamp(minWidth, cap);
}
