import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/kanban/kanban_card_surface.dart';
import 'package:kanban/features/project/project_settings.dart';

void main() {
  test('卡片不透明度允许 0–100%，默认 35%', () {
    expect(ProjectSettings.minCardSurfaceOpacity, 0.0);
    expect(ProjectSettings.maxCardSurfaceOpacity, 1.0);
    expect(ProjectSettings.defaultCardSurfaceOpacity, 0.35);
    expect(ProjectSettings.clampCardSurfaceOpacity(0), 0.0);
    expect(ProjectSettings.clampCardSurfaceOpacity(0.1), 0.1);
    expect(ProjectSettings.clampCardSurfaceOpacity(-0.2), 0.0);
    expect(ProjectSettings.clampCardSurfaceOpacity(1.4), 1.0);
  });

  test('遮罩默认 0，范围仍从 0 起', () {
    expect(ProjectSettings.defaultBackgroundOverlayOpacity, 0.0);
    expect(ProjectSettings.clampOverlayOpacity(0), 0.0);
  });

  test('卡片表面色的 alpha 跟随不透明度，0 与 1 可区分', () {
    const solid = Color(0xFF112233);
    final transparent = kanbanCardSurfaceColor(solid: solid, opacity: 0);
    final tinted = kanbanCardSurfaceColor(solid: solid, opacity: 0.35);
    final opaque = kanbanCardSurfaceColor(solid: solid, opacity: 1);
    expect(transparent.a, 0);
    expect(tinted.a, closeTo(0.35, 0.001));
    expect(opaque.a, 1);
    expect(transparent, isNot(equals(opaque)));
  });
}
