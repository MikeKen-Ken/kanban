import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/controllers/board_controller.dart';
import 'package:kanban/features/agent_dispatch/card_agent_conversation_section.dart';
import 'package:kanban/storage/board_storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late BoardController controller;
  late String cardId;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kanban_agent_followup_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    controller = await BoardController.createForTest(
      prefs: prefs,
      storage: BoardStorage(baseDirectory: tempDir, prefs: prefs),
    );
    final id = await controller.addCard('todo', '待追问卡');
    cardId = id!;
  });

  tearDown(() async {
    controller.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('提交追问后关闭对话并通知上层同步', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var parentSynced = false;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          home: Scaffold(
            body: CardAgentConversationSection(
              cardId: cardId,
              onConversationChanged: () async {
                parentSynced = true;
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('card-agent-conversation-open')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Submit follow-up'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('card-agent-conversation-input')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('card-agent-conversation-input')),
      '请默认关闭窗口',
    );
    expect(find.text('请默认关闭窗口'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('Submit follow-up'));
      await tester.pump();
      await Future<void>.delayed(const Duration(seconds: 3));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final live = controller.findCardById(cardId)!;
    expect(
      live.verificationFeedback.map((item) => item.text).toList(),
      contains('Agent follow-up: 请默认关闭窗口'),
    );
    expect(parentSynced, isTrue);
    expect(live.agentConversationMarkdown, contains('请默认关闭窗口'));
    expect(controller.findColumnIdForCard(cardId), 'rework');
  });

  testWidgets('点关闭退出对话并通知上层同步', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var parentSynced = false;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          home: Scaffold(
            body: CardAgentConversationSection(
              cardId: cardId,
              onConversationChanged: () async {
                parentSynced = true;
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('card-agent-conversation-open')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Close'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Submit follow-up'), findsNothing);
    expect(parentSynced, isTrue);
  });

  testWidgets('输入非空时点空白等同提交追问', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var parentSynced = false;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          home: Scaffold(
            body: CardAgentConversationSection(
              cardId: cardId,
              onConversationChanged: () async {
                parentSynced = true;
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('card-agent-conversation-open')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.byKey(const ValueKey('card-agent-conversation-input')),
      '点空白也要提交',
    );
    expect(find.text('点空白也要提交'), findsOneWidget);

    await tester.runAsync(() async {
      final barrier = tester.getRect(
        find.byKey(const ValueKey('card-agent-conversation-barrier')),
      );
      await tester.tapAt(barrier.topLeft + const Offset(8, 8));
      await tester.pump();
      await Future<void>.delayed(const Duration(seconds: 3));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final live = controller.findCardById(cardId)!;
    expect(
      live.verificationFeedback.map((item) => item.text).toList(),
      contains('Agent follow-up: 点空白也要提交'),
    );
    expect(parentSynced, isTrue);
    expect(live.agentConversationMarkdown, contains('点空白也要提交'));
    expect(controller.findColumnIdForCard(cardId), 'rework');
  });

  testWidgets('输入为空时点空白只关闭对话', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var parentSynced = false;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          home: Scaffold(
            body: CardAgentConversationSection(
              cardId: cardId,
              onConversationChanged: () async {
                parentSynced = true;
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('card-agent-conversation-open')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final emptyBarrier = tester.getRect(
      find.byKey(const ValueKey('card-agent-conversation-barrier')),
    );
    await tester.tapAt(emptyBarrier.topLeft + const Offset(8, 8));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Submit follow-up'), findsNothing);
    expect(parentSynced, isTrue);
    expect(controller.findCardById(cardId)!.verificationFeedback, isEmpty);
    expect(controller.findColumnIdForCard(cardId), 'todo');
  });
}

