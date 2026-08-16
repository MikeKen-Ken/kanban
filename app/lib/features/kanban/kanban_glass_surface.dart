import 'dart:ui';

import 'package:flutter/material.dart';

/// 接近 iOS 液态玻璃的磨砂层：背景模糊、低密度着色与高光描边。
class KanbanGlassSurface extends StatelessWidget {
  const KanbanGlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.tint,
    this.borderColor,
    this.borderWidth = 1,
    this.blurSigma = 24,
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
    // 不预先 alphaBlend 高光与底色：预混会累积两层 alpha，让浅色主题
    // 看起来接近实色。直接使用低密度渐变，让壁纸细节交给模糊层呈现。
    final fillTop = base.withValues(alpha: isDark ? 0.24 : 0.30);
    final fillMiddle = base.withValues(alpha: isDark ? 0.17 : 0.20);
    final fillBottom = base.withValues(alpha: isDark ? 0.12 : 0.14);
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
              colors: [fillTop, fillMiddle, fillBottom],
              stops: const [0, 0.42, 1],
            ),
            border: Border.all(color: edge, width: borderWidth),
          ),
          child: child,
        ),
      ),
    );
  }
}
