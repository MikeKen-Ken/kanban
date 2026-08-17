import 'package:flutter/material.dart';

import '../project/project_settings.dart';

/// 看板卡片表面色：不透明度直接作用在底色 alpha 上，文字仍由前景色绘制。
Color kanbanCardSurfaceColor({
  required Color solid,
  required double opacity,
}) {
  return solid.withValues(
    alpha: ProjectSettings.clampCardSurfaceOpacity(opacity),
  );
}
