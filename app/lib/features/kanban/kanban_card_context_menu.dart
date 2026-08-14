import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 卡片右键菜单命中目标：用于在关闭菜单后按坐标重新定位到另一张卡片。
class CardContextMenuHost extends SingleChildRenderObjectWidget {
  const CardContextMenuHost({
    super.key,
    required this.onContextMenu,
    required super.child,
  });

  final void Function(Offset globalPosition) onContextMenu;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderCardContextMenuHost(onContextMenu);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCardContextMenuHost renderObject,
  ) {
    renderObject.onContextMenu = onContextMenu;
  }
}

class _RenderCardContextMenuHost extends RenderProxyBox {
  _RenderCardContextMenuHost(this.onContextMenu);

  void Function(Offset globalPosition) onContextMenu;

  void invoke(Offset globalPosition) => onContextMenu(globalPosition);
}

/// 关闭当前菜单后，在 [globalPosition] 下查找卡片并重新弹出菜单。
void retargetKanbanCardContextMenu(
  Offset globalPosition,
  BuildContext context,
) {
  final result = HitTestResult();
  final view = View.maybeOf(context);
  if (view == null) return;
  GestureBinding.instance.hitTestInView(result, globalPosition, view.viewId);
  for (final entry in result.path) {
    final target = entry.target;
    if (target is _RenderCardContextMenuHost) {
      target.invoke(globalPosition);
      return;
    }
  }
}

/// 卡片右键菜单：左键关闭；在其它卡片上右键时关闭当前菜单并立即在新卡片弹出。
Future<T?> showKanbanCardContextMenu<T>({
  required BuildContext context,
  required Offset globalPosition,
  required List<PopupMenuEntry<T>> items,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 80),
    transitionBuilder: (context, animation, secondaryAnimation, child) => child,
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return _KanbanCardContextMenuOverlay<T>(
        globalPosition: globalPosition,
        items: items,
        rootContext: context,
        animation: animation,
      );
    },
  );
}

class _KanbanCardContextMenuOverlay<T> extends StatelessWidget {
  const _KanbanCardContextMenuOverlay({
    required this.globalPosition,
    required this.items,
    required this.rootContext,
    required this.animation,
  });

  final Offset globalPosition;
  final List<PopupMenuEntry<T>> items;
  final BuildContext rootContext;
  final Animation<double> animation;

  RelativeRect _menuPosition(BuildContext context) {
    final overlay =
        Overlay.of(rootContext).context.findRenderObject() as RenderBox?;
    final overlaySize = overlay?.size ?? MediaQuery.sizeOf(context);
    if (overlay == null) {
      return RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        overlaySize.width - globalPosition.dx,
        overlaySize.height - globalPosition.dy,
      );
    }
    final local = overlay.globalToLocal(globalPosition);
    return RelativeRect.fromLTRB(
      local.dx,
      local.dy,
      overlaySize.width - local.dx,
      overlaySize.height - local.dy,
    );
  }

  void _onBarrierPointerDown(BuildContext context, PointerDownEvent event) {
    if (event.buttons == kPrimaryMouseButton) {
      Navigator.of(context).pop();
      return;
    }
    if (event.buttons == kSecondaryMouseButton) {
      final position = event.position;
      Navigator.of(context).pop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        retargetKanbanCardContextMenu(position, rootContext);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final popupTheme = theme.popupMenuTheme;
    final position = _menuPosition(context);
    final padding =
        popupTheme.menuPadding?.resolve(Directionality.of(context)) ??
        const EdgeInsets.symmetric(vertical: 8);

    final menuPanel = Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (event.buttons == kSecondaryMouseButton) {
          Navigator.of(context).pop();
        }
      },
      child: Material(
        elevation: popupTheme.elevation ?? 8,
        shadowColor: theme.shadowColor,
        surfaceTintColor: popupTheme.surfaceTintColor,
        color: popupTheme.color ?? theme.colorScheme.surface,
        shape: popupTheme.shape ??
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: items,
          ),
        ),
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) => _onBarrierPointerDown(context, event),
          ),
        ),
        CustomSingleChildLayout(
          delegate: _PopupMenuPositionDelegate(position, padding),
          child: FadeTransition(opacity: animation, child: menuPanel),
        ),
      ],
    );
  }
}

class _PopupMenuPositionDelegate extends SingleChildLayoutDelegate {
  _PopupMenuPositionDelegate(this.position, this.padding);

  final RelativeRect position;
  final EdgeInsets padding;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(
      Size(
        constraints.maxWidth - position.left - position.right,
        constraints.maxHeight - position.top - position.bottom,
      ),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var x = position.left;
    var y = position.top;
    if (x + childSize.width > size.width - position.right) {
      x = size.width - position.right - childSize.width;
    }
    if (y + childSize.height > size.height - position.bottom) {
      y = size.height - position.bottom - childSize.height;
    }
    if (x < position.left) x = position.left;
    if (y < position.top) y = position.top;
    return Offset(x + padding.left, y + padding.top);
  }

  @override
  bool shouldRelayout(covariant _PopupMenuPositionDelegate oldDelegate) {
    return position != oldDelegate.position || padding != oldDelegate.padding;
  }
}
