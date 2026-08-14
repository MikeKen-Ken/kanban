import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/project/project_quick_switch.dart';
import 'sync_actions_sheet.dart';

/// 右上角同步快速选择：按住稍候出现列表，上下滑动高亮，松手确认。
class SyncQuickSwitchGesture extends StatefulWidget {
  const SyncQuickSwitchGesture({
    super.key,
    required this.longPressDelay,
    required this.onCommit,
    required this.child,
  });

  final Duration longPressDelay;
  final Future<void> Function(SyncManualAction action) onCommit;
  final Widget child;

  static const double itemExtent = ProjectQuickSwitchGesture.itemExtent;
  static const double panelMinWidth = ProjectQuickSwitchGesture.panelMinWidth;
  static const double panelMaxWidth = ProjectQuickSwitchGesture.panelMaxWidth;
  static const double panelPaddingV = ProjectQuickSwitchGesture.panelPaddingV;

  @override
  State<SyncQuickSwitchGesture> createState() => _SyncQuickSwitchGestureState();
}

class _SyncQuickSwitchGestureState extends State<SyncQuickSwitchGesture> {
  OverlayEntry? _overlayEntry;
  int _highlightedIndex = 0;
  int _startIndex = 0;
  Offset _startGlobal = Offset.zero;
  double _panelTop = 0;
  bool _sessionActive = false;
  bool _globalRouteAttached = false;
  bool _scrubPointerInterrupted = false;

  static const _actions = SyncManualAction.values;

  @override
  void dispose() {
    _detachGlobalPointerRoute();
    _removeOverlay();
    super.dispose();
  }

  void _attachGlobalPointerRoute() {
    if (_globalRouteAttached) return;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_handleGlobalPointer);
    _globalRouteAttached = true;
  }

  void _detachGlobalPointerRoute() {
    if (!_globalRouteAttached) return;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_handleGlobalPointer);
    _globalRouteAttached = false;
  }

  void _handleGlobalPointer(PointerEvent event) {
    if (!_sessionActive) return;

    if (event is PointerCancelEvent) {
      _scrubPointerInterrupted = true;
      return;
    }

    if (event is PointerUpEvent) {
      unawaited(_endSession(commit: true));
      return;
    }

    final held = event.down || event.buttons != 0;
    if (event is PointerDownEvent ||
        event is PointerMoveEvent ||
        event is PointerHoverEvent) {
      if (held) {
        _updateSession(event.position);
      } else if (_scrubPointerInterrupted &&
          (event is PointerMoveEvent || event is PointerHoverEvent)) {
        unawaited(_endSession(commit: true));
      }
    }
  }

  double _localYForGlobal(double globalY) {
    return globalY - _panelTop - SyncQuickSwitchGesture.panelPaddingV;
  }

  int _indexForGlobal(Offset globalPosition) {
    return projectQuickSwitchIndexAtY(
      localY: _localYForGlobal(globalPosition.dy),
      itemExtent: SyncQuickSwitchGesture.itemExtent,
      length: _actions.length,
    );
  }

  void _applyHighlight(int next, {required bool haptic}) {
    if (next == _highlightedIndex) return;
    _highlightedIndex = next;
    if (haptic) HapticFeedback.selectionClick();
    _overlayEntry?.markNeedsBuild();
  }

  void _startSession(Offset globalPosition) {
    _startIndex = _indexForGlobal(globalPosition);
    _highlightedIndex = _startIndex;
    _startGlobal = globalPosition;
    _sessionActive = true;
    _scrubPointerInterrupted = false;
    _attachGlobalPointerRoute();
    _insertOverlay();
    HapticFeedback.mediumImpact();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_sessionActive) return;
      _applyHighlight(_indexForGlobal(_startGlobal), haptic: false);
    });
  }

  void _updateSession(Offset globalPosition) {
    if (!_sessionActive) return;
    _applyHighlight(_indexForGlobal(globalPosition), haptic: true);
  }

  Future<void> _endSession({required bool commit}) async {
    if (!_sessionActive) return;
    final index = _highlightedIndex;
    final shouldCommit =
        commit && index >= 0 && index < _actions.length;
    final action = shouldCommit ? _actions[index] : null;
    _removeOverlay();
    if (action != null) {
      await widget.onCommit(action);
    }
  }

  double _computePanelTop({
    required MediaQueryData media,
    required double panelHeight,
  }) {
    var top = _startGlobal.dy -
        SyncQuickSwitchGesture.panelPaddingV -
        (_startIndex + 0.5) * SyncQuickSwitchGesture.itemExtent;
    return top.clamp(
      media.padding.top + 8,
      media.size.height - media.padding.bottom - panelHeight - 8,
    );
  }

  void _insertOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) {
      _sessionActive = false;
      return;
    }

    final media = MediaQuery.of(context);
    final contentHeight = SyncQuickSwitchGesture.panelPaddingV * 2 +
        _actions.length * SyncQuickSwitchGesture.itemExtent;
    final maxPanelHeight = media.size.height * 0.7;
    final panelHeight = contentHeight.clamp(0.0, maxPanelHeight);
    _panelTop = _computePanelTop(media: media, panelHeight: panelHeight);

    _overlayEntry = OverlayEntry(
      builder: (ctx) {
        final overlayMedia = MediaQuery.of(ctx);
        final theme = Theme.of(ctx);
        final top = _panelTop;
        final left = (_startGlobal.dx - 24).clamp(
          8.0,
          overlayMedia.size.width - SyncQuickSwitchGesture.panelMinWidth - 8,
        );

        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerMove: (e) {
            if (!_sessionActive) return;
            if (e.buttons != 0 || e.down) {
              _updateSession(e.position);
            }
          },
          onPointerUp: (e) {
            if (!_sessionActive) return;
            unawaited(_endSession(commit: true));
          },
          onPointerCancel: (_) {},
          child: Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.18),
                ),
              ),
              Positioned(
                left: left,
                top: top,
                child: IgnorePointer(
                  child: Material(
                    elevation: 10,
                    borderRadius: BorderRadius.circular(12),
                    color: theme.colorScheme.surface,
                    clipBehavior: Clip.antiAlias,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: SyncQuickSwitchGesture.panelMinWidth,
                        maxWidth: SyncQuickSwitchGesture.panelMaxWidth,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: SyncQuickSwitchGesture.panelPaddingV,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < _actions.length; i++)
                              _SyncQuickSwitchTile(
                                action: _actions[i],
                                selected: i == _highlightedIndex,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    overlay.insert(_overlayEntry!);
    _highlightedIndex = _indexForGlobal(_startGlobal);
  }

  void _removeOverlay() {
    _detachGlobalPointerRoute();
    _sessionActive = false;
    _scrubPointerInterrupted = false;
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: <Type, GestureRecognizerFactory>{
        ScrubGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<ScrubGestureRecognizer>(
          () => ScrubGestureRecognizer(
            holdDuration: widget.longPressDelay,
            supportedDevices: _supportedDevices,
          ),
          (instance) {
            instance.onStart = _startSession;
            instance.onUpdate = _updateSession;
            instance.onEnd = () {
              unawaited(_endSession(commit: true));
            };
            instance.onCancel = () {
              unawaited(_endSession(commit: false));
            };
          },
        ),
      },
      child: widget.child,
    );
  }

  static final Set<PointerDeviceKind> _supportedDevices = {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.unknown,
  };
}

class _SyncQuickSwitchTile extends StatelessWidget {
  const _SyncQuickSwitchTile({
    required this.action,
    required this.selected,
  });

  final SyncManualAction action;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bg = selected
        ? scheme.primaryContainer.withValues(alpha: 0.95)
        : Colors.transparent;
    final onTile =
        selected ? scheme.onPrimaryContainer : scheme.onSurface;

    return SizedBox(
      height: SyncQuickSwitchGesture.itemExtent,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 18,
              color: selected ? scheme.primary : onTile.withValues(alpha: 0.55),
            ),
            const SizedBox(width: 10),
            Icon(action.icon, size: 18, color: onTile),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                action.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: onTile,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
