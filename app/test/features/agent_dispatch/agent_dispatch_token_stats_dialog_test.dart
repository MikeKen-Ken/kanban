import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kanban/features/agent_dispatch/agent_dispatch_token_stats_dialog.dart';

void main() {
  test('Token 统计界面不含官网口径说明', () {
    final source = File(
      'lib/features/agent_dispatch/agent_dispatch_token_stats_dialog.dart',
    ).readAsStringSync();
    expect(source.contains('口径与官网'), isFalse);
    expect(source.contains('不把缓存再计入'), isFalse);
    expect(source.contains('与官网一致'), isFalse);
  });

  testWidgets('Esc 优先关闭 Token 统计界面', (tester) async {
    var parentShortcutTriggered = false;

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                parentShortcutTriggered = true,
          },
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showAgentDispatchTokenStatsDialog(
                context: context,
                projectId: 'project-1',
              ),
              child: const Text('打开统计'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开统计'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Token 统计'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Token 统计'), findsNothing);
    expect(parentShortcutTriggered, isFalse);
  });
}
