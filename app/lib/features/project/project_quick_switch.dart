import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'projects_manifest.dart';
import 'project_theme.dart';

/// 根据垂直位移计算快速切换高亮索引（相对起始项）。
int projectQuickSwitchIndex({
  required int startIndex,
  required double dy,
  required double itemExtent,
  required int length,
}) {
  if (length <= 0) return 0;
  if (itemExtent <= 0) return startIndex.clamp(0, length - 1);
  final next = startIndex + (dy / itemExtent).round();
  return next.clamp(0, length - 1);
}

/// 左上角项目快速切换：按住稍候出现列表，上下滑动高亮，松手确认。
class ProjectQuickSwitchGesture extends StatefulWidget {
  const ProjectQuickSwitchGesture({
    super.key,
    required this.projects,
    required this.activeProjectId,
    required this.longPressDelay,
    required this.themeIdFor,
    required this.onCommit,
    required this.child,
  });

  final List<ProjectEntry> projects;
  final String? activeProjectId;
  final Duration longPressDelay;
  final String Function(String projectId) themeIdFor;
  final Future<void> Function(String projectId) onCommit;
  final Widget child;

  static const double itemExtent = 44;
  static const double panelMinWidth = 220;
  static const double panelMaxWidth = 320;
  static const double panelPaddingV = 8;

  @override
  State<ProjectQuickSwitchGesture> createState() =>
      _ProjectQuickSwitchGestureState();
}

class _ProjectQuickSwitchGestureState extends State<ProjectQuickSwitchGesture> {
  OverlayEntry? _overlayEntry;
  final ScrollController _scrollController = ScrollController();
  int _highlightedIndex = 0;
  int _startIndex = 0;
  Offset _startGlobal = Offset.zero;
  bool _sessionActive = false;

  @override
  void dispose() {
    _removeOverlay();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ProjectQuickSwitchGesture oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sessionActive) return;
    if (widget.projects.isEmpty) {
      _removeOverlay();
      return;
    }
    _highlightedIndex =
        _highlightedIndex.clamp(0, widget.projects.length - 1);
    _overlayEntry?.markNeedsBuild();
  }

  int _indexOfActive() {
    final id = widget.activeProjectId;
    if (id == null) return 0;
    final i = widget.projects.indexWhere((p) => p.id == id);
    return i >= 0 ? i : 0;
  }

  void _startSession(Offset globalPosition) {
    if (widget.projects.length <= 1) return;
    _startIndex = _indexOfActive();
    _highlightedIndex = _startIndex;
    _startGlobal = globalPosition;
    _sessionActive = true;
    _insertOverlay();
    HapticFeedback.mediumImpact();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureHighlightedVisible();
    });
  }

  void _updateSession(Offset globalPosition) {
    if (!_sessionActive || widget.projects.isEmpty) return;
    final dy = globalPosition.dy - _startGlobal.dy;
    final next = projectQuickSwitchIndex(
      startIndex: _startIndex,
      dy: dy,
      itemExtent: ProjectQuickSwitchGesture.itemExtent,
      length: widget.projects.length,
    );
    if (next == _highlightedIndex) return;
    _highlightedIndex = next;
    HapticFeedback.selectionClick();
    _overlayEntry?.markNeedsBuild();
    _ensureHighlightedVisible();
  }

  Future<void> _endSession({required bool commit}) async {
    if (!_sessionActive) return;
    final projects = widget.projects;
    final index = _highlightedIndex;
    final shouldCommit = commit &&
        projects.isNotEmpty &&
        index >= 0 &&
        index < projects.length;
    final targetId = shouldCommit ? projects[index].id : null;
    _removeOverlay();
    if (targetId != null && targetId != widget.activeProjectId) {
      await widget.onCommit(targetId);
    }
  }

  void _ensureHighlightedVisible() {
    if (!_scrollController.hasClients) return;
    final targetOffset =
        _highlightedIndex * ProjectQuickSwitchGesture.itemExtent;
    final view = _scrollController.position;
    if (targetOffset < view.pixels) {
      _scrollController.jumpTo(targetOffset);
    } else if (targetOffset + ProjectQuickSwitchGesture.itemExtent >
        view.pixels + view.viewportDimension) {
      _scrollController.jumpTo(
        (targetOffset + ProjectQuickSwitchGesture.itemExtent -
                view.viewportDimension)
            .clamp(0.0, view.maxScrollExtent),
      );
    }
  }

  void _insertOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) {
      _sessionActive = false;
      return;
    }

    _overlayEntry = OverlayEntry(
      builder: (ctx) {
        final media = MediaQuery.of(ctx);
        final theme = Theme.of(ctx);
        final brightness = theme.brightness;
        final projects = widget.projects;
        final anchor = _startGlobal;

        final contentHeight = ProjectQuickSwitchGesture.panelPaddingV * 2 +
            projects.length * ProjectQuickSwitchGesture.itemExtent;
        final maxPanelHeight = media.size.height * 0.7;
        final panelHeight = contentHeight.clamp(0.0, maxPanelHeight);

        // 让起始项中心大致对齐按压点，滑动过程中面板位置固定
        var top = anchor.dy -
            ProjectQuickSwitchGesture.panelPaddingV -
            (_startIndex + 0.5) * ProjectQuickSwitchGesture.itemExtent;
        top = top.clamp(
          media.padding.top + 8,
          media.size.height - media.padding.bottom - panelHeight - 8,
        );

        var left = anchor.dx - 24;
        left = left.clamp(
          8.0,
          media.size.width - ProjectQuickSwitchGesture.panelMinWidth - 8,
        );

        return IgnorePointer(
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
                child: Material(
                  elevation: 10,
                  borderRadius: BorderRadius.circular(12),
                  color: theme.colorScheme.surface,
                  clipBehavior: Clip.antiAlias,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: ProjectQuickSwitchGesture.panelMinWidth,
                      maxWidth: ProjectQuickSwitchGesture.panelMaxWidth,
                      maxHeight: maxPanelHeight,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: ProjectQuickSwitchGesture.panelPaddingV,
                      ),
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < projects.length; i++)
                              _QuickSwitchTile(
                                project: projects[i],
                                selected: i == _highlightedIndex,
                                isActive:
                                    projects[i].id == widget.activeProjectId,
                                seed: _seedColor(
                                  widget.themeIdFor(projects[i].id),
                                  brightness,
                                ),
                                brightness: brightness,
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
  }

  Color _seedColor(String themeId, Brightness brightness) {
    final preset = projectThemeForId(themeId);
    return brightness == Brightness.dark ? preset.seedDark : preset.seedLight;
  }

  void _removeOverlay() {
    _sessionActive = false;
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: <Type, GestureRecognizerFactory>{
        _ProjectScrubGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<_ProjectScrubGestureRecognizer>(
          () => _ProjectScrubGestureRecognizer(
            holdDuration: widget.longPressDelay,
            supportedDevices: _supportedDevices,
          ),
          (instance) {
            instance.onStart = _startSession;
            instance.onUpdate = _updateSession;
            instance.onEnd = () {
              _endSession(commit: true);
            };
            instance.onCancel = () {
              _endSession(commit: false);
            };
          },
        ),
      },
      child: widget.child,
    );
  }

  /// 桌面鼠标与移动触摸均支持。
  static final Set<PointerDeviceKind> _supportedDevices = {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.unknown,
  };
}

/// 稍长按住，或按住后垂直拖过阈值，均可进入快速切换；短按仍留给子组件菜单。
class _ProjectScrubGestureRecognizer extends OneSequenceGestureRecognizer {
  _ProjectScrubGestureRecognizer({
    required this.holdDuration,
    required super.supportedDevices,
  });

  final Duration holdDuration;

  /// 垂直拖动超过该阈值时提前进入快速切换（无需静止等满长按）。
  static const double verticalActivateSlop = 12;

  void Function(Offset globalPosition)? onStart;
  void Function(Offset globalPosition)? onUpdate;
  VoidCallback? onEnd;
  VoidCallback? onCancel;

  Timer? _holdTimer;
  Offset? _origin;
  int? _pointer;
  bool _accepted = false;

  @override
  String get debugDescription => 'projectQuickSwitchScrub';

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _resetTracking();
    _pointer = event.pointer;
    _origin = event.position;
    _holdTimer = Timer(holdDuration, () {
      if (_accepted || _origin == null) return;
      _accept(_origin!);
    });
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _pointer) return;

    if (event is PointerMoveEvent) {
      final origin = _origin;
      if (origin == null) return;
      if (_accepted) {
        onUpdate?.call(event.position);
        return;
      }

      final dx = event.position.dx - origin.dx;
      final dy = event.position.dy - origin.dy;
      if (dy.abs() >= verticalActivateSlop && dy.abs() > dx.abs()) {
        _accept(origin);
        onUpdate?.call(event.position);
        return;
      }
      // 明显非垂直移动则放弃，避免抢走短按菜单
      if (event.localDelta.distance > kTouchSlop && dx.abs() >= dy.abs()) {
        _rejectPending();
      }
      return;
    }

    if (event is PointerUpEvent || event is PointerCancelEvent) {
      final wasAccepted = _accepted;
      final cancelled = event is PointerCancelEvent;
      _clearTimer();
      stopTrackingPointer(event.pointer);
      if (wasAccepted) {
        if (cancelled) {
          onCancel?.call();
        } else {
          onEnd?.call();
        }
      } else {
        resolve(GestureDisposition.rejected);
      }
      _resetTracking();
    }
  }

  @override
  void acceptGesture(int pointer) {}

  @override
  void rejectGesture(int pointer) {
    if (pointer != _pointer) return;
    final wasAccepted = _accepted;
    _clearTimer();
    if (wasAccepted) {
      onCancel?.call();
    }
    _resetTracking();
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  void _accept(Offset origin) {
    if (_accepted) return;
    _accepted = true;
    _clearTimer();
    resolve(GestureDisposition.accepted);
    onStart?.call(origin);
  }

  void _rejectPending() {
    _clearTimer();
    if (_pointer != null) {
      stopTrackingPointer(_pointer!);
    }
    resolve(GestureDisposition.rejected);
    _resetTracking();
  }

  void _clearTimer() {
    _holdTimer?.cancel();
    _holdTimer = null;
  }

  void _resetTracking() {
    _clearTimer();
    _pointer = null;
    _origin = null;
    _accepted = false;
  }
}

class _QuickSwitchTile extends StatelessWidget {
  const _QuickSwitchTile({
    required this.project,
    required this.selected,
    required this.isActive,
    required this.seed,
    required this.brightness,
  });

  final ProjectEntry project;
  final bool selected;
  final bool isActive;
  final Color seed;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final bg = selected
        ? scheme.primaryContainer.withValues(alpha: 0.95)
        : Colors.transparent;
    final onTile = selected
        ? scheme.onPrimaryContainer
        : Theme.of(context).colorScheme.onSurface;

    return SizedBox(
      height: ProjectQuickSwitchGesture.itemExtent,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              selected || isActive
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              size: 18,
              color: selected ? scheme.primary : onTile.withValues(alpha: 0.55),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                project.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: onTile,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            if (project.hasConflict)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(
                  '冲突',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
