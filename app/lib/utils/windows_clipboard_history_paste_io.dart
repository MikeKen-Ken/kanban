import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';

/// 安装 Windows 剪贴板历史（Win+V）粘贴修复。
///
/// Flutter Windows embedder 无法正确解析剪贴板历史注入的合成 Ctrl+V 键序列，
/// 导致选中历史项后无法填入 TextField。见 flutter/flutter#143997。
void installWindowsClipboardHistoryPasteFix() {
  if (!Platform.isWindows) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    WindowsClipboardHistoryKeyFix.instance.install();
  });
}

/// 将损坏的 Win+V 键序列纠正为正常 Ctrl+V。
///
/// 暴露供单测；运行时由 [installWindowsClipboardHistoryPasteFix] 挂到
/// [PlatformDispatcher.onKeyData]。
class WindowsClipboardHistoryKeyFix {
  WindowsClipboardHistoryKeyFix();

  static final instance = WindowsClipboardHistoryKeyFix();

  static const int _controlLeftPhysical = 0x700e0;
  static const int _controlLeftLogical = 0x200000100;
  static const int _vPhysical = 0x70019;
  static const int _vLogical = 0x76;
  static const int _brokenPhysical = 0x1600000000;

  bool _active = false;
  bool _installed = false;

  @visibleForTesting
  bool get isActive => _active;

  /// 纠正单条键数据。返回应转发的 [KeyData]；返回 `null` 表示吞掉该事件。
  @visibleForTesting
  KeyData? rewrite(KeyData data) {
    if (!_active &&
        data.physical == _brokenPhysical &&
        data.logical == _controlLeftLogical &&
        data.type == KeyEventType.down &&
        !data.synthesized) {
      _active = true;
      return KeyData(
        timeStamp: data.timeStamp,
        type: KeyEventType.down,
        physical: _controlLeftPhysical,
        logical: _controlLeftLogical,
        character: null,
        synthesized: false,
      );
    }

    if (_active &&
        data.physical == 0 &&
        data.logical == 0 &&
        data.type == KeyEventType.down &&
        !data.synthesized) {
      return null;
    }

    if (_active &&
        data.physical == _brokenPhysical &&
        data.logical == _controlLeftLogical &&
        data.type == KeyEventType.up &&
        !data.synthesized) {
      return KeyData(
        timeStamp: data.timeStamp,
        type: KeyEventType.down,
        physical: _vPhysical,
        logical: _vLogical,
        character: null,
        synthesized: false,
      );
    }

    if (_active &&
        data.physical == _brokenPhysical &&
        data.logical == _controlLeftLogical &&
        data.type == KeyEventType.down &&
        data.synthesized) {
      return KeyData(
        timeStamp: data.timeStamp,
        type: KeyEventType.up,
        physical: _vPhysical,
        logical: _vLogical,
        character: null,
        synthesized: false,
      );
    }

    if (_active &&
        data.physical == _brokenPhysical &&
        data.logical == _controlLeftLogical &&
        data.type == KeyEventType.up &&
        data.synthesized) {
      _active = false;
      return KeyData(
        timeStamp: data.timeStamp,
        type: KeyEventType.up,
        physical: _controlLeftPhysical,
        logical: _controlLeftLogical,
        character: null,
        synthesized: false,
      );
    }

    _active = false;
    return data;
  }

  void install() {
    if (_installed) return;
    final KeyDataCallback? original = PlatformDispatcher.instance.onKeyData;
    if (original == null) return;

    _installed = true;
    PlatformDispatcher.instance.onKeyData = (KeyData data) {
      final rewritten = rewrite(data);
      if (rewritten == null) return true;
      return original(rewritten);
    };
  }

  @visibleForTesting
  void reset() {
    _active = false;
  }
}
