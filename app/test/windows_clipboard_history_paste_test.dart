import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kanban/utils/windows_clipboard_history_paste_io.dart';

void main() {
  late WindowsClipboardHistoryKeyFix fix;

  KeyData key({
    required KeyEventType type,
    required int physical,
    required int logical,
    bool synthesized = false,
  }) {
    return KeyData(
      timeStamp: Duration.zero,
      type: type,
      physical: physical,
      logical: logical,
      character: null,
      synthesized: synthesized,
    );
  }

  setUp(() {
    fix = WindowsClipboardHistoryKeyFix()..reset();
  });

  test('Win+V 损坏键序列触发一次粘贴并被完整吞掉', () {
    var pasteCount = 0;
    fix = WindowsClipboardHistoryKeyFix(onPaste: () => pasteCount++);

    // 序列来自 flutter/flutter#143997 社区 workaround
    final events = <KeyData>[
      key(
        type: KeyEventType.down,
        physical: 0x1600000000,
        logical: 0x200000100,
      ),
      key(type: KeyEventType.down, physical: 0, logical: 0),
      key(
        type: KeyEventType.up,
        physical: 0x1600000000,
        logical: 0x200000100,
      ),
      key(
        type: KeyEventType.down,
        physical: 0x1600000000,
        logical: 0x200000100,
        synthesized: true,
      ),
      key(
        type: KeyEventType.up,
        physical: 0x1600000000,
        logical: 0x200000100,
        synthesized: true,
      ),
    ];

    for (final event in events) {
      expect(fix.rewrite(event), isNull);
    }

    expect(pasteCount, 1);
    expect(fix.isActive, isFalse);
  });

  testWidgets('Win+V 历史项会填入当前输入框', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextField(controller: controller, autofocus: true),
        ),
      ),
    );
    await tester.pump();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': '历史内容'};
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final result = WindowsClipboardHistoryKeyFix().rewrite(
      key(
        type: KeyEventType.down,
        physical: 0x1600000000,
        logical: 0x200000100,
      ),
    );
    await tester.pump();

    expect(result, isNull);
    expect(controller.text, '历史内容');
  });

  test('普通按键原样转发且不会卡住 active', () {
    final original = key(
      type: KeyEventType.down,
      physical: 0x70004,
      logical: 0x61,
    );
    final out = fix.rewrite(original);
    expect(identical(out, original) || out == original, isTrue);
    expect(fix.isActive, isFalse);
  });
}
