import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kanban/features/kanban/kanban_card_context_menu.dart';

void main() {
  testWidgets('卡片右键菜单可见且左键可关闭', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () {
                    showKanbanCardContextMenu<String>(
                      context: context,
                      globalPosition: const Offset(120, 80),
                      items: const [
                        PopupMenuItem<String>(
                          value: 'copy',
                          child: Text('复制'),
                        ),
                      ],
                    );
                  },
                  child: const Text('open-menu'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open-menu'));
    await tester.pumpAndSettle();

    expect(find.text('复制'), findsOneWidget);
    final menuSize = tester.getSize(find.text('复制'));
    expect(menuSize.width, greaterThan(8));
    expect(menuSize.height, greaterThan(8));

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.text('复制'), findsNothing);
  });
}
