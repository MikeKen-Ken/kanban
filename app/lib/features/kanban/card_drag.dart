import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 拖拽反馈卡片中心对准指针（而非左上角）。
///
/// [feedbackWidth] 应与反馈层实际宽度一致。
Offset feedbackCenterDragAnchorStrategy(
  Draggable<Object> draggable,
  BuildContext context,
  Offset position, {
  required double feedbackWidth,
}) {
  final box = context.findRenderObject() as RenderBox?;
  final height = (box != null && box.hasSize) ? box.size.height : 80.0;
  return Offset(feedbackWidth / 2, height / 2);
}

/// 长按未完成或拖拽已开始时，是否应抑制打开卡片详情。
///
/// [heldMs] 为按下到抬起的时长；阈值取拖拽延迟的 35%，并夹在 120ms～延迟之间。
bool shouldSuppressCardTapAfterPress({
  required int heldMs,
  required int dragLongPressMs,
  required bool dragStarted,
}) {
  if (dragStarted) return true;
  if (dragLongPressMs <= 0) return false;
  final threshold =
      (dragLongPressMs * 0.35).round().clamp(120, dragLongPressMs);
  return heldMs >= threshold;
}

/// 长按延迟拖拽：阈值内不因位移自行拒绝，明显滑动时由外层滚动手势胜出。
class CardLongPressDraggable<T extends Object> extends LongPressDraggable<T> {
  const CardLongPressDraggable({
    super.key,
    required super.child,
    required super.feedback,
    super.data,
    super.axis,
    super.childWhenDragging,
    super.feedbackOffset,
    super.dragAnchorStrategy,
    super.maxSimultaneousDrags,
    super.onDragStarted,
    super.onDragUpdate,
    super.onDraggableCanceled,
    super.onDragEnd,
    super.onDragCompleted,
    super.hapticFeedbackOnStart,
    super.ignoringFeedbackSemantics,
    super.ignoringFeedbackPointer,
    super.delay,
    super.allowedButtonsFilter,
    super.hitTestBehavior,
    super.rootOverlay,
  });

  @override
  DelayedMultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) {
    return _CardDelayedMultiDragGestureRecognizer(
        delay: delay,
        allowedButtonsFilter: allowedButtonsFilter,
      )
      ..onStart = (Offset position) {
        final Drag? result = onStart(position);
        if (result != null && hapticFeedbackOnStart) {
          HapticFeedback.selectionClick();
        }
        return result;
      };
  }
}

/// 与 [DelayedMultiDragGestureRecognizer] 相同，但阈值内移动不自行 reject。
class _CardDelayedMultiDragGestureRecognizer
    extends DelayedMultiDragGestureRecognizer {
  _CardDelayedMultiDragGestureRecognizer({
    required super.delay,
    super.allowedButtonsFilter,
  });

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) {
    return _CardDelayedPointerState(
      event.position,
      delay,
      event.kind,
      gestureSettings,
    );
  }

  @override
  String get debugDescription => 'card delayed multi drag';
}

class _CardDelayedPointerState extends MultiDragPointerState {
  _CardDelayedPointerState(
    Offset initialPosition,
    this.delay,
    PointerDeviceKind kind,
    DeviceGestureSettings? gestureSettings,
  ) : super(initialPosition, kind, gestureSettings) {
    _timer = Timer(delay, _delayPassed);
  }

  final Duration delay;
  Timer? _timer;
  GestureMultiDragStartCallback? _starter;

  void _delayPassed() {
    assert(_timer != null);
    assert(pendingDelta != null);
    _timer = null;
    if (_starter != null) {
      _starter!(initialPosition);
      _starter = null;
    } else {
      resolve(GestureDisposition.accepted);
    }
  }

  void _ensureTimerStopped() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) {
    assert(_starter == null);
    if (_timer == null) {
      starter(initialPosition);
    } else {
      _starter = starter;
    }
  }

  @override
  void checkForResolutionAfterMove() {
    // 不在阈值内因位移 reject：微移/提前挪动仍可进入拖拽；
    // 明显滚动由 ListView 等在手势竞技场中胜出。
  }

  @override
  void dispose() {
    _ensureTimerStopped();
    super.dispose();
  }
}
