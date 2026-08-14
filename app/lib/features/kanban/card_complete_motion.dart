import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// 完成勾选、详情按钮与卡片飞入已完成列的时序。
abstract final class CardCompleteMotion {
  static const checkbox = Duration(milliseconds: 280);
  static const button = Duration(milliseconds: 240);
  static const flight = Duration(milliseconds: 400);
}

/// 完成飞行期间隐藏源/目标实体卡，只保留 Overlay 上的飞行副本。
class CardCompleteFlightController extends ChangeNotifier {
  String? _flyingCardId;

  String? get flyingCardId => _flyingCardId;

  bool hides(String cardId) => _flyingCardId == cardId;

  void begin(String cardId) {
    if (_flyingCardId == cardId) return;
    _flyingCardId = cardId;
    notifyListeners();
  }

  void end() {
    if (_flyingCardId == null) return;
    _flyingCardId = null;
    notifyListeners();
  }
}

/// 卡片与列在屏幕上的布局锚点，供完成飞行读取起终点。
///
/// 同一卡片可能出现在多条泳道，因此按实例登记，而不是全局 [GlobalKey]。
class CardLayoutRegistry {
  CardLayoutRegistry._();

  static final CardLayoutRegistry instance = CardLayoutRegistry._();

  final Map<String, List<State>> _cards = {};
  final Map<String, List<State>> _columns = {};

  void _register(Map<String, List<State>> map, String id, State state) {
    final list = map.putIfAbsent(id, () => <State>[]);
    if (!list.contains(state)) list.add(state);
  }

  void _unregister(Map<String, List<State>> map, String id, State state) {
    final list = map[id];
    if (list == null) return;
    list.remove(state);
    if (list.isEmpty) map.remove(id);
  }

  void registerCard(String cardId, State state) =>
      _register(_cards, cardId, state);

  void unregisterCard(String cardId, State state) =>
      _unregister(_cards, cardId, state);

  void registerColumn(String columnId, State state) =>
      _register(_columns, columnId, state);

  void unregisterColumn(String columnId, State state) =>
      _unregister(_columns, columnId, state);

  Rect? rectForCard(String cardId, {Size? screenSize}) =>
      _bestRect(_cards[cardId], screenSize: screenSize);

  Rect? rectForColumn(String columnId, {Size? screenSize}) =>
      _bestRect(_columns[columnId], screenSize: screenSize);

  Rect? resolveFlightTarget({
    required String cardId,
    String? doneColumnId,
    required Size screenSize,
  }) {
    final cardRect = rectForCard(cardId, screenSize: screenSize);
    if (cardRect != null &&
        isRectOnScreen(cardRect, screenSize, minVisible: 24)) {
      return cardRect;
    }
    if (doneColumnId != null) {
      final columnRect = rectForColumn(doneColumnId, screenSize: screenSize);
      if (columnRect != null &&
          isRectOnScreen(columnRect, screenSize, minVisible: 24)) {
        final width = cardRect?.width ?? math.min(280, columnRect.width - 16);
        final height = cardRect?.height ?? 72;
        return Rect.fromLTWH(
          columnRect.left + 8,
          columnRect.bottom - height - 12,
          width,
          height,
        );
      }
      if (cardRect != null) return cardRect;
      if (columnRect != null) return columnRect;
    }
    return cardRect;
  }
}

Rect? _bestRect(List<State>? states, {Size? screenSize}) {
  if (states == null || states.isEmpty) return null;
  Rect? fallback;
  for (final state in states) {
    final rect = _rectOfState(state);
    if (rect == null) continue;
    fallback ??= rect;
    if (screenSize != null &&
        isRectOnScreen(rect, screenSize, minVisible: 24)) {
      return rect;
    }
  }
  return fallback;
}

Rect? _rectOfState(State state) {
  if (!state.mounted) return null;
  final box = state.context.findRenderObject();
  if (box is! RenderBox || !box.hasSize || !box.attached) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// 把当前布局登记到 [CardLayoutRegistry]，可同时存在多个实例。
class CardLayoutAnchor extends StatefulWidget {
  const CardLayoutAnchor.card({
    super.key,
    required this.cardId,
    required this.child,
  }) : columnId = null;

  const CardLayoutAnchor.column({
    super.key,
    required this.columnId,
    required this.child,
  }) : cardId = null;

  final String? cardId;
  final String? columnId;
  final Widget child;

  @override
  State<CardLayoutAnchor> createState() => _CardLayoutAnchorState();
}

class _CardLayoutAnchorState extends State<CardLayoutAnchor> {
  @override
  void initState() {
    super.initState();
    _register();
  }

  @override
  void didUpdateWidget(covariant CardLayoutAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cardId != widget.cardId ||
        oldWidget.columnId != widget.columnId) {
      _unregister(oldWidget);
      _register();
    }
  }

  @override
  void dispose() {
    _unregister(widget);
    super.dispose();
  }

  void _register() {
    final cardId = widget.cardId;
    final columnId = widget.columnId;
    if (cardId != null) {
      CardLayoutRegistry.instance.registerCard(cardId, this);
    }
    if (columnId != null) {
      CardLayoutRegistry.instance.registerColumn(columnId, this);
    }
  }

  void _unregister(CardLayoutAnchor target) {
    final cardId = target.cardId;
    final columnId = target.columnId;
    if (cardId != null) {
      CardLayoutRegistry.instance.unregisterCard(cardId, this);
    }
    if (columnId != null) {
      CardLayoutRegistry.instance.unregisterColumn(columnId, this);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

bool isRectOnScreen(
  Rect rect,
  Size screenSize, {
  double minVisible = 48,
}) {
  final overlap = rect.intersect(Offset.zero & screenSize);
  if (overlap.isEmpty) return false;
  return overlap.width >= minVisible && overlap.height >= minVisible;
}

/// 飞行路径：线性插值矩形，并叠加一条向上的短弧。
Rect flightRectAt({
  required Rect from,
  required Rect to,
  required double t,
  double arcHeight = 28,
}) {
  final clamped = t.clamp(0.0, 1.0);
  final lerped = Rect.lerp(from, to, clamped)!;
  final arc = -arcHeight * math.sin(math.pi * clamped);
  return lerped.shift(Offset(0, arc));
}

double flightScaleAt(double t, {double destScale = 1}) {
  final clamped = t.clamp(0.0, 1.0);
  final base = 1 + (destScale - 1) * clamped;
  return base * (1 + 0.045 * math.sin(math.pi * clamped));
}

double flightOpacityAt(double t, {required bool fadeOut}) {
  if (!fadeOut) return 1;
  final clamped = t.clamp(0.0, 1.0);
  if (clamped < 0.45) return 1;
  return (1 - (clamped - 0.45) / 0.55).clamp(0.0, 1.0);
}

CardCompleteFlightController? _maybeFlightController(
  BuildContext context, {
  bool listen = true,
}) {
  try {
    return Provider.of<CardCompleteFlightController>(context, listen: listen);
  } on ProviderNotFoundException {
    return null;
  }
}

/// 飞行期间把实体卡隐去，避免与 Overlay 副本叠成两张。
class CardFlightHidden extends StatelessWidget {
  const CardFlightHidden({
    super.key,
    required this.cardId,
    required this.child,
  });

  final String cardId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final controller = _maybeFlightController(context);
    final hidden = controller?.hides(cardId) ?? false;
    if (!hidden) return child;
    return IgnorePointer(
      ignoring: true,
      child: Opacity(
        opacity: 0,
        child: child,
      ),
    );
  }
}

/// 将卡片从 [fromRect] 飞到已完成列；[mutate] 负责真正改看板。
///
/// 返回 [mutate] 的错误文案。无动画、无起点或系统关闭动画时直接突变。
Future<String?> playCardCompleteFlight({
  required BuildContext context,
  required String cardId,
  Rect? fromRect,
  required Widget replica,
  required Future<String?> Function() mutate,
  String? doneColumnId,
}) async {
  if (!context.mounted) return mutate();
  if (fromRect == null || MediaQuery.disableAnimationsOf(context)) {
    return mutate();
  }

  final overlayState = Overlay.of(context, rootOverlay: true);
  final flight = _maybeFlightController(context, listen: false);
  final screenSize = MediaQuery.sizeOf(context);
  final startRect = fromRect;

  final rectListenable = ValueNotifier<Rect>(startRect);
  final scaleListenable = ValueNotifier<double>(1);
  final opacityListenable = ValueNotifier<double>(1);

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) {
      return IgnorePointer(
        child: Material(
          type: MaterialType.transparency,
          child: ValueListenableBuilder<Rect>(
            valueListenable: rectListenable,
            builder: (context, rect, _) {
              return ValueListenableBuilder<double>(
                valueListenable: scaleListenable,
                builder: (context, scale, _) {
                  return ValueListenableBuilder<double>(
                    valueListenable: opacityListenable,
                    builder: (context, opacity, _) {
                      return Stack(
                        children: [
                          Positioned(
                            left: rect.left,
                            top: rect.top,
                            width: rect.width,
                            height: rect.height,
                            child: Opacity(
                              opacity: opacity,
                              child: Transform.scale(
                                scale: scale,
                                child: replica,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      );
    },
  );

  overlayState.insert(entry);
  flight?.begin(cardId);

  String? error;
  try {
    error = await mutate();
    if (error != null) return error;

    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;

    final target = CardLayoutRegistry.instance.resolveFlightTarget(
          cardId: cardId,
          doneColumnId: doneColumnId,
          screenSize: screenSize,
        ) ??
        startRect.translate(96, -28);
    final fadeOut = !isRectOnScreen(target, screenSize, minVisible: 24);
    final destScale = startRect.width <= 0 ? 1.0 : target.width / startRect.width;

    final controller = AnimationController(
      vsync: overlayState,
      duration: CardCompleteMotion.flight,
    );
    final curved = CurvedAnimation(
      parent: controller,
      curve: Curves.easeInOutCubic,
    );
    void tick() {
      final t = curved.value;
      rectListenable.value = flightRectAt(from: startRect, to: target, t: t);
      scaleListenable.value = flightScaleAt(t, destScale: destScale);
      opacityListenable.value = flightOpacityAt(t, fadeOut: fadeOut);
    }

    curved.addListener(tick);
    try {
      await controller.forward();
    } finally {
      curved.removeListener(tick);
      controller.dispose();
    }
    return null;
  } finally {
    entry.remove();
    flight?.end();
    rectListenable.dispose();
    scaleListenable.dispose();
    opacityListenable.dispose();
  }
}
