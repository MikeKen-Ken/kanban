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
  WindowsClipboardHistoryKeyFix({VoidCallback? onPaste})
      : _onPaste = onPaste ?? _pasteIntoFocusedTextField;

  static final instance = WindowsClipboardHistoryKeyFix();

  static const int _controlLeftLogical = 0x200000100;
  static const int _brokenPhysical = 0x1600000000;

  final VoidCallback _onPaste;
  bool _active = false;
  bool _installed = false;

  @visibleForTesting
  bool get isActive => _active;

  /// 处理单条键数据。返回 `null` 表示已处理并吞掉该事件。
  ///
  /// 识别到剪贴板历史注入序列时直接调用 Flutter 的粘贴动作，避免再把
  /// 损坏事件伪造成 Ctrl+V 后交给 [HardwareKeyboard] 的按键状态机。
  @visibleForTesting
  KeyData? rewrite(KeyData data) {
    if (!_active &&
        data.physical == _brokenPhysical &&
        data.logical == _controlLeftLogical &&
        data.type == KeyEventType.down &&
        !data.synthesized) {
      _active = true;
      _onPaste();
      return null;
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
        (data.type == KeyEventType.up || data.synthesized)) {
      if (data.type == KeyEventType.up && data.synthesized) {
        _active = false;
      }
      return null;
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

  static void _pasteIntoFocusedTextField() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return;
    Actions.maybeInvoke(
      context,
      const PasteTextIntent(SelectionChangedCause.keyboard),
    );
  }

  @visibleForTesting
  void reset() {
    _active = false;
  }
}
