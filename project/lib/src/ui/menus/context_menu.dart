import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../theme/tokens.dart';

/// One row in a context menu.
class MenuItem {
  const MenuItem.button(
    this.label, {
    this.icon,
    this.onTap,
    this.destructive = false,
    this.trailing,
    this.keepOpen = false,
    this.sublabel,
    this.capitalise = true,
  }) : children = null,
       custom = null,
       divider = false;
  const MenuItem.sub(
    this.label, {
    this.icon,
    required List<MenuItem> this.children,
    this.onTap,
    this.destructive = false,
  }) : trailing = null,
       custom = null,
       divider = false,
       keepOpen = false,
       sublabel = null,
       capitalise = true;
  const MenuItem.divider()
    : label = null,
      icon = null,
      onTap = null,
      destructive = false,
      trailing = null,
      children = null,
      custom = null,
      divider = true,
      keepOpen = false,
      sublabel = null,
      capitalise = true;
  const MenuItem.custom(Widget this.custom)
    : label = null,
      icon = null,
      onTap = null,
      destructive = false,
      trailing = null,
      children = null,
      divider = false,
      keepOpen = false,
      sublabel = null,
      capitalise = true;

  final String? label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool destructive, divider, keepOpen, capitalise;
  final String? sublabel;
  final Widget? trailing;
  final List<MenuItem>? children;
  final Widget? custom;
}

String _capitalise(String s) => s.splitMapJoin(
  RegExp(r'\S+'),
  onMatch: (m) => m[0]![0].toUpperCase() + m[0]!.substring(1),
  onNonMatch: (s) => s,
);

/// Shows a floating context menu next to [position] (global coordinates).
Future<void> showContextMenu(BuildContext context, Offset position, List<MenuItem> items) {
  final cleaned = _tidy(items);
  if (cleaned.isEmpty) return Future.value();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (c, _, _) => _MenuHost(position: position, items: cleaned),
    transitionBuilder: (c, a, _, child) => FadeTransition(opacity: a, child: child),
  );
}

List<MenuItem> _tidy(List<MenuItem> items) {
  final out = <MenuItem>[];
  for (final i in items) {
    if (i.divider && (out.isEmpty || out.last.divider)) continue;
    out.add(i);
  }
  while (out.isNotEmpty && out.last.divider) {
    out.removeLast();
  }
  return out;
}

class _MenuHost extends StatelessWidget {
  const _MenuHost({required this.position, required this.items});
  final Offset position;
  final List<MenuItem> items;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Stack(
      children: [
        CustomSingleChildLayout(
          delegate: _MenuLayout(position, size),
          child: MenuPanel(items: items, onClose: () => Navigator.of(context).pop()),
        ),
      ],
    );
  }
}

class _MenuLayout extends SingleChildLayoutDelegate {
  _MenuLayout(this.pos, this.screen);
  final Offset pos;
  final Size screen;
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints c) =>
      BoxConstraints(maxWidth: 280, maxHeight: screen.height - 16);
  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var x = pos.dx, y = pos.dy;
    if (x + childSize.width > size.width - 8) x = size.width - childSize.width - 8;
    if (y + childSize.height > size.height - 8) y = size.height - childSize.height - 8;
    return Offset(x < 8 ? 8 : x, y < 8 ? 8 : y);
  }

  @override
  bool shouldRelayout(_MenuLayout old) => old.pos != pos || old.screen != screen;
}

class MenuPanel extends StatelessWidget {
  const MenuPanel({super.key, required this.items, required this.onClose});
  final List<MenuItem> items;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainer,
      elevation: 3,
      shadowColor: cs.shadow,
      borderRadius: br(Radius_.xs),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicWidth(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 180),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: Gap.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [for (final i in items) _Row(item: i, onClose: onClose)],
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({required this.item, required this.onClose});
  final MenuItem item;
  final VoidCallback onClose;
  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  final _link = LayerLink();
  OverlayEntry? _sub;

  @override
  void dispose() {
    _sub?.remove();
    super.dispose();
  }

  void _openSub() {
    if (_sub != null) return;
    _sub = OverlayEntry(
      builder: (c) => CompositedTransformFollower(
        link: _link,
        targetAnchor: Alignment.topRight,
        followerAnchor: Alignment.topLeft,
        offset: const Offset(5, 0),
        showWhenUnlinked: false,
        child: Align(
          alignment: Alignment.topLeft,
          child: MenuPanel(items: widget.item.children!, onClose: widget.onClose),
        ),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_sub!);
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.item;
    final cs = Theme.of(context).colorScheme;
    if (i.divider) {
      return Container(height: 1, margin: const EdgeInsets.symmetric(vertical: Gap.sm), color: cs.outlineVariant);
    }
    if (i.custom != null) return i.custom!;
    final colour = i.destructive ? cs.error : cs.onSurface;
    final isSub = i.children != null;
    return CompositedTransformTarget(
      link: _link,
      child: InkWell(
        hoverColor: cs.onSurface.withValues(alpha: .08),
        onTap: () {
          if (isSub) {
            if (i.onTap != null) {
              widget.onClose();
              i.onTap!();
            } else {
              _openSub();
            }
            return;
          }
          if (!i.keepOpen) widget.onClose();
          i.onTap?.call();
        },
        onHover: (h) {
          if (isSub && h) _openSub();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (i.icon != null) ...[Icon(i.icon, size: 16, color: colour), const SizedBox(width: Gap.md)],
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(i.capitalise ? _capitalise(tr(i.label ?? '')) : tr(i.label ?? ''), style: TextStyle(color: colour, fontSize: 14)),
                    if (i.sublabel != null) Text(tr(i.sublabel!), style: TextStyle(color: cs.outline, fontSize: 12)),
                  ],
                ),
              ),
              if (i.trailing != null) ...[const SizedBox(width: Gap.md), i.trailing!],
              if (isSub) ...[const SizedBox(width: 24), Icon(Icons.chevron_right, size: 20, color: colour)],
            ],
          ),
        ),
      ),
    );
  }
}

/// Wraps a child so that right-click and long-press open [builder]'s menu.
class ContextMenuRegion extends StatelessWidget {
  const ContextMenuRegion({super.key, required this.child, required this.builder, this.behavior = HitTestBehavior.deferToChild});
  final Widget child;
  final List<MenuItem> Function(BuildContext context) builder;
  final HitTestBehavior behavior;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: behavior,
    onSecondaryTapUp: (d) => showContextMenu(context, d.globalPosition, builder(context)),
    onLongPressStart: (d) => showContextMenu(context, d.globalPosition, builder(context)),
    child: child,
  );
}
