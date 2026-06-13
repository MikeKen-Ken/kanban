import 'package:flutter/material.dart';

/// 在中文等 IME 组字期间延迟 [setState]，避免输入框出现方框/乱码。
mixin ImeGuard<T extends StatefulWidget> on State<T> {
  bool _deferredRebuild = false;

  bool isComposing(TextEditingController controller) =>
      controller.value.composing.isValid;

  bool isAnyComposing(Iterable<TextEditingController> controllers) =>
      controllers.any(isComposing);

  /// 组字中只执行 [fn] 并标记待刷新，否则正常 [setState]。
  void imeSafeSetState(VoidCallback fn, Iterable<TextEditingController> controllers) {
    if (isAnyComposing(controllers)) {
      fn();
      _deferredRebuild = true;
    } else {
      setState(fn);
    }
  }

  /// 外部刷新（如 Provider）在组字期间也应延迟。
  void deferRebuildIfComposing(Iterable<TextEditingController> controllers) {
    if (isAnyComposing(controllers)) {
      _deferredRebuild = true;
    } else if (mounted) {
      setState(() {});
    }
  }

  void bindImeGuard(Iterable<TextEditingController> controllers) {
    for (final controller in controllers) {
      controller.addListener(() => _flushDeferredRebuild(controllers));
    }
  }

  void _flushDeferredRebuild(Iterable<TextEditingController> controllers) {
    if (_deferredRebuild && !isAnyComposing(controllers) && mounted) {
      _deferredRebuild = false;
      setState(() {});
    }
  }
}
