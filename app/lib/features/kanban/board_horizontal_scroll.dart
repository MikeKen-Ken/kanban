import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 将指针滚轮增量映射为看板横向滚动距离。
///
/// 鼠标滚轮通常只有 [Offset.dy]；触控板在横向手势下可能以 [Offset.dx] 为主。
@visibleForTesting
double boardHorizontalScrollDelta(Offset scrollDelta) {
  return scrollDelta.dx.abs() > scrollDelta.dy.abs()
      ? scrollDelta.dx
      : scrollDelta.dy;
}

/// 计算 Ctrl+滚轮后的目标偏移，并夹在可滚动范围内。
@visibleForTesting
double clampBoardScrollOffset({
  required double pixels,
  required double delta,
  required double minScrollExtent,
  required double maxScrollExtent,
}) {
  return (pixels + delta).clamp(minScrollExtent, maxScrollExtent);
}

/// 在按住 Ctrl 时认领滚轮事件，并驱动 [controller] 横向滚动。
///
/// 未按 Ctrl 时不处理，以便列内纵向滚动等默认行为不受影响。
bool tryClaimCtrlWheelForBoardScroll({
  required PointerSignalEvent event,
  required ScrollController controller,
  required bool isControlPressed,
}) {
  if (event is! PointerScrollEvent) return false;
  if (!isControlPressed) return false;
  if (!controller.hasClients) return false;

  GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
    final scrollEvent = resolved as PointerScrollEvent;
    if (!controller.hasClients) return;
    final position = controller.position;
    final delta = boardHorizontalScrollDelta(scrollEvent.scrollDelta);
    final target = clampBoardScrollOffset(
      pixels: position.pixels,
      delta: delta,
      minScrollExtent: position.minScrollExtent,
      maxScrollExtent: position.maxScrollExtent,
    );
    if (target != position.pixels) {
      controller.jumpTo(target);
    }
  });
  return true;
}

/// 按住 Ctrl 时拒绝滚轮/拖拽滚动，好让外层认领 Ctrl+滚轮。
class _RejectWhenCtrlScrollPhysics extends ScrollPhysics {
  const _RejectWhenCtrlScrollPhysics({super.parent});

  @override
  _RejectWhenCtrlScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _RejectWhenCtrlScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) {
    if (HardwareKeyboard.instance.isControlPressed) {
      return false;
    }
    return super.shouldAcceptUserOffset(position);
  }
}

class _BoardHorizontalScrollBehavior extends MaterialScrollBehavior {
  const _BoardHorizontalScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return _RejectWhenCtrlScrollPhysics(
      parent: super.getScrollPhysics(context),
    );
  }
}

/// 看板主视图横向滚动壳：共享控制器的可拖动滚动条 + Ctrl+滚轮左右滚动。
class BoardHorizontalScroll extends StatefulWidget {
  const BoardHorizontalScroll({
    super.key,
    required this.builder,
  });

  /// 构建横向可滚动内容，必须把 [controller] 交给内部 ScrollView。
  final Widget Function(BuildContext context, ScrollController controller)
      builder;

  @override
  State<BoardHorizontalScroll> createState() => _BoardHorizontalScrollState();
}

class _BoardHorizontalScrollState extends State<BoardHorizontalScroll> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    tryClaimCtrlWheelForBoardScroll(
      event: event,
      controller: _controller,
      isControlPressed: HardwareKeyboard.instance.isControlPressed,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: const _BoardHorizontalScrollBehavior(),
      child: Listener(
        onPointerSignal: _onPointerSignal,
        child: Scrollbar(
          controller: _controller,
          // 溢出时保持可见，便于发现并可拖动。
          thumbVisibility: true,
          interactive: true,
          child: widget.builder(context, _controller),
        ),
      ),
    );
  }
}
