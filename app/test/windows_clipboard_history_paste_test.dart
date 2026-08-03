import 'dart:ui';

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

  test('Win+V 损坏键序列被纠正为 Ctrl+V', () {
    // 序列来自 flutter/flutter#143997 社区 workaround
    final ctrlDown = fix.rewrite(
      key(
        type: KeyEventType.down,
        physical: 0x1600000000,
        logical: 0x200000100,
      ),
    );
    expect(ctrlDown, isNotNull);
    expect(ctrlDown!.physical, 0x700e0);
    expect(ctrlDown.logical, 0x200000100);
    expect(ctrlDown.type, KeyEventType.down);
    expect(fix.isActive, isTrue);

    expect(
      fix.rewrite(
        key(type: KeyEventType.down, physical: 0, logical: 0),
      ),
      isNull,
    );

    final vDown = fix.rewrite(
      key(
        type: KeyEventType.up,
        physical: 0x1600000000,
        logical: 0x200000100,
      ),
    );
    expect(vDown!.physical, 0x70019);
    expect(vDown.logical, 0x76);
    expect(vDown.type, KeyEventType.down);

    final vUp = fix.rewrite(
      key(
        type: KeyEventType.down,
        physical: 0x1600000000,
        logical: 0x200000100,
        synthesized: true,
      ),
    );
    expect(vUp!.physical, 0x70019);
    expect(vUp.type, KeyEventType.up);

    final ctrlUp = fix.rewrite(
      key(
        type: KeyEventType.up,
        physical: 0x1600000000,
        logical: 0x200000100,
        synthesized: true,
      ),
    );
    expect(ctrlUp!.physical, 0x700e0);
    expect(ctrlUp.type, KeyEventType.up);
    expect(fix.isActive, isFalse);
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
