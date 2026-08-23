import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/features/kanban/kanban_glass_surface.dart';

void main() {
  test('kanbanGlassBlur uses clamp to avoid transparent edge sampling', () {
    expect(
      kanbanGlassBlur(28),
      ImageFilter.blur(sigmaX: 28, sigmaY: 28, tileMode: TileMode.clamp),
    );
  });

  testWidgets('zero blur skips the backdrop filter', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: KanbanGlassSurface(
          blurSigma: 0,
          child: SizedBox(width: 100, height: 100),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('positive blur keeps the configured backdrop filter',
      (tester) async {
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
