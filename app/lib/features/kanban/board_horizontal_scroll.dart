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

/// 计算修饰键+滚轮后的目标偏移，并夹在可滚动范围内。
@visibleForTesting
double clampBoardScrollOffset({
  required double pixels,
  required double delta,
  required double minScrollExtent,
  required double maxScrollExtent,
}) {
  return (pixels + delta).clamp(minScrollExtent, maxScrollExtent);
}

/// 当前焦点是否在可编辑文本内（输入框打字时不应把空格当横滚修饰键）。
@visibleForTesting
bool isEditableTextFocused([FocusNode? primaryFocus]) {
  final focus = primaryFocus ?? FocusManager.instance.primaryFocus;
  final context = focus?.context;
  if (context == null) return false;
  if (context.widget is EditableText) return true;
  return context.findAncestorWidgetOfExactType<EditableText>() != null;
}

/// 是否应将滚轮认领为看板横向滚动。
///
/// - Ctrl：始终可作为横滚修饰键（与是否在输入框无关）。
/// - 空格：仅在未聚焦可编辑文本时生效，避免抢走输入框里的空格打字语义。
@visibleForTesting
bool shouldClaimBoardHorizontalWheel({
  required bool isControlPressed,
  required bool isSpacePressed,
  required bool isEditableFocused,
}) {
  if (isControlPressed) return true;
  if (isSpacePressed && !isEditableFocused) return true;
  return false;
}

/// 当前是否应按修饰键认领看板横向滚轮（读取硬件键盘与焦点状态）。
@visibleForTesting
bool isBoardHorizontalWheelModifierActive() {
  return shouldClaimBoardHorizontalWheel(
    isControlPressed: HardwareKeyboard.instance.isControlPressed,
    isSpacePressed: HardwareKeyboard.instance.isLogicalKeyPressed(
      LogicalKeyboardKey.space,
    ),
    isEditableFocused: isEditableTextFocused(),
  );
}

/// 在列内认领纵向滚轮，避免外层横向 [Scrollable] 吞掉垂直增量。
///
/// 修饰键横滚激活时不认领，以便外层看板接管滚轮。
bool tryClaimVerticalWheelForColumnScroll({
  required PointerSignalEvent event,
  required ScrollController controller,
}) {
  if (event is! PointerScrollEvent) return false;
  if (isBoardHorizontalWheelModifierActive()) return false;
  if (!controller.hasClients) return false;

  final delta = event.scrollDelta.dy;
  if (delta == 0) return false;

  GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
    final scrollEvent = resolved as PointerScrollEvent;
    if (!controller.hasClients) return;
    final position = controller.position;
    final verticalDelta = scrollEvent.scrollDelta.dy;
    if (verticalDelta == 0) return;
    final target = clampBoardScrollOffset(
      pixels: position.pixels,
      delta: verticalDelta,
      minScrollExtent: position.minScrollExtent,
      maxScrollExtent: position.maxScrollExtent,
    );
    if (target != position.pixels) {
      controller.jumpTo(target);
    }
  });
  return true;
}

/// 在按住 Ctrl 或（非输入焦点下的）空格时认领滚轮，并驱动 [controller] 横向滚动。
///
/// 未按修饰键时不处理，以便列内纵向滚动等默认行为不受影响。
bool tryClaimModifierWheelForBoardScroll({
  required PointerSignalEvent event,
  required ScrollController controller,
  required bool claimHorizontal,
}) {
  if (event is! PointerScrollEvent) return false;
  if (!claimHorizontal) return false;
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

/// 按住 Ctrl 或（非输入焦点下）空格时拒绝滚轮/拖拽滚动，好让外层认领横滚。
class _RejectWhenHorizontalModifierScrollPhysics extends ScrollPhysics {
  const _RejectWhenHorizontalModifierScrollPhysics({super.parent});

  @override
  _RejectWhenHorizontalModifierScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _RejectWhenHorizontalModifierScrollPhysics(
      parent: buildParent(ancestor),
    );
  }

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) {
    if (isBoardHorizontalWheelModifierActive()) return false;
    return super.shouldAcceptUserOffset(position);
  }
}

class _BoardHorizontalScrollBehavior extends MaterialScrollBehavior {
  const _BoardHorizontalScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return _RejectWhenHorizontalModifierScrollPhysics(
      parent: super.getScrollPhysics(context),
    );
  }
}

/// 看板主视图横向滚动壳：共享控制器的可拖动滚动条 + Ctrl/空格+滚轮左右滚动。
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
    tryClaimModifierWheelForBoardScroll(
      event: event,
      controller: _controller,
      claimHorizontal: isBoardHorizontalWheelModifierActive(),
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
