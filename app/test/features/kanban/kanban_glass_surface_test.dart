import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/kanban/kanban_glass_surface.dart';

void main() {
  test('kanbanGlassBlur 使用 clamp，避免边缘采到透明像素', () {
    expect(
      kanbanGlassBlur(28),
      ImageFilter.blur(sigmaX: 28, sigmaY: 28, tileMode: TileMode.clamp),
    );
  });

  testWidgets('KanbanGlassSurface 使用同一套边缘钳制模糊', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: KanbanGlassSurface(
            blurSigma: 24,
            child: SizedBox(width: 40, height: 40),
          ),
        ),
      ),
    );

    final filter = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(filter.filter, kanbanGlassBlur(24));
  });
}
