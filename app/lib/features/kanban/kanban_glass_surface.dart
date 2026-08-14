import 'dart:ui';

import 'package:flutter/material.dart';

/// 接近 iOS 液态玻璃的磨砂层：背景模糊、浅色渐变与高光描边。
class KanbanGlassSurface extends StatelessWidget {
  const KanbanGlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.tint,
    this.borderColor,
    this.borderWidth = 1,
    this.blurSigma = 22,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final Color? tint;
  final Color? borderColor;
  final double borderWidth;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = tint ?? colorScheme.surface;
    final highlight = isDark
        ? Colors.white.withValues(alpha: 0.22)
        : Colors.white.withValues(alpha: 0.55);
    final fillTop = Color.alphaBlend(
      highlight.withValues(alpha: isDark ? 0.10 : 0.28),
      base.withValues(alpha: isDark ? 0.22 : 0.32),
    );
    final fillBottom = base.withValues(alpha: isDark ? 0.18 : 0.22);
    final edge = borderColor ??
        (isDark
            ? Colors.white.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.62));

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [fillTop, fillBottom],
            ),
            border: Border.all(color: edge, width: borderWidth),
          ),
          child: child,
        ),
      ),
    );
  }
}
