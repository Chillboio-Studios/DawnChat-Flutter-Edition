import 'package:flutter/material.dart';

import 'net_image.dart';

import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/client_store.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../core/i18n.dart';

Future<void> openUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || url == '#') return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(tr(message))));
}

String errorText(Object e) => e.toString();

Future<void> copyText(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showSnack(context, 'Copied!');
}

class Wordmark extends StatefulWidget {
  const Wordmark({super.key, this.width = 148, this.color});
  final double width;
  final Color? color;

  static Future<String>? _svg;

  @override
  State<Wordmark> createState() => _WordmarkState();
}

class _WordmarkState extends State<Wordmark> {
  @override
  Widget build(BuildContext context) {
    Wordmark._svg ??= rootBundle.loadString('assets/branding/wordmark.svg');
    final color = widget.color ?? context.cs.onSurface;
    final hex =
        '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    return FutureBuilder<String>(
      future: Wordmark._svg,
      builder: (c, snap) => SizedBox(
        width: widget.width,
        height: widget.width * 230.25 / 806.88,
        child: snap.hasData
            ? SvgPicture.string(
                snap.data!.replaceAll('fill="#000000"', 'fill="$hex"'),
                width: widget.width,
              )
            : null,
      ),
    );
  }
}

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.userId,
    this.size = 36,
    this.showStatus = false,
    this.fallbackName,
    this.url,
  });

  final String? userId;
  final double size;
  final bool showStatus;
  final String? fallbackName;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final src = url ?? store.avatarUrl(userId, size: size * 2);
    final avatar = ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: src == null
            ? _Fallback(name: fallbackName ?? store.displayName(userId))
            : NetImage(
                src,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    _Fallback(name: fallbackName ?? store.displayName(userId)),
              ),
      ),
    );
    if (!showStatus) return avatar;
    final u = store.user(userId);
    final online = u?['online'] == true;
    final presence = online
        ? ((u?['status'] as Map?)?['presence'] as String? ?? 'Online')
        : null;
    final d = size * 0.34;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            right: -d * 0.1,
            bottom: -d * 0.1,
            child: Container(
              width: d + 4,
              height: d + 4,
              decoration: BoxDecoration(
                color: context.cs.surfaceContainerHigh,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Container(
                width: d,
                height: d,
                decoration: BoxDecoration(
                  color: StatusColors.of(presence),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.name});
  final String name;
  @override
  Widget build(BuildContext context) => Container(
    color: context.cs.primaryContainer,
    alignment: Alignment.center,
    child: Text(
      name.isEmpty ? '?' : name.characters.first.toUpperCase(),
      style: TextStyle(
        color: context.cs.onPrimaryContainer,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class IconAvatar extends StatelessWidget {
  const IconAvatar({
    super.key,
    this.url,
    required this.name,
    this.size = 32,
    this.square = true,
  });
  final String? url;
  final String name;
  final double size;
  final bool square;

  @override
  Widget build(BuildContext context) {
    final child = SizedBox.square(
      dimension: size,
      child: url == null
          ? _Fallback(name: name)
          : NetImage(
              url!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _Fallback(name: name),
            ),
    );
    return square
        ? ClipRRect(borderRadius: br(size * 0.3), child: child)
        : ClipOval(child: child);
  }
}

/// Material You list tile used throughout the sidebars (web `MenuButton`).
class MenuButton extends StatelessWidget {
  const MenuButton({
    super.key,
    required this.title,
    this.leading,
    this.trailing,
    this.selected = false,
    this.muted = false,
    this.active = false,
    this.onTap,
    this.onLongPress,
    this.subtitle,
    this.height = 40,
  });

  final Widget title;
  final Widget? leading;
  final Widget? trailing;
  final Widget? subtitle;
  final bool selected;
  final bool muted;
  final bool active;
  final double height;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final fg = selected
        ? cs.onSecondaryContainer
        : muted
        ? cs.outline
        : active
        ? cs.onSurface
        : cs.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md),
      child: Material(
        color: selected ? cs.secondaryContainer : Colors.transparent,
        borderRadius: br(Radius_.xl),
        child: InkWell(
          borderRadius: br(Radius_.xl),
          onTap: onTap,
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: height),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.l,
                vertical: 4,
              ),
              child: Row(
                children: [
                  if (leading != null) ...[
                    IconTheme(
                      data: IconThemeData(color: fg, size: 22),
                      child: leading!,
                    ),
                    const SizedBox(width: Gap.l),
                  ],
                  Expanded(
                    child: DefaultTextStyle.merge(
                      style: TextStyle(
                        color: fg,
                        fontWeight: active || selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          title,
                          if (subtitle != null)
                            DefaultTextStyle.merge(
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                color: cs.outline,
                              ),
                              child: subtitle!,
                            ),
                        ],
                      ),
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Settings row (web `CategoryButton`); groups round only their outer corners.
class CategoryButton extends StatelessWidget {
  const CategoryButton({
    super.key,
    required this.title,
    this.description,
    this.icon,
    this.action,
    this.onTap,
    this.destructive = false,
  });

  final Widget title;
  final Widget? description;
  final Widget? icon;
  final Widget? action;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.l + 4,
          vertical: Gap.md,
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: br(Radius_.md),
                ),
                child: IconTheme(
                  data: IconThemeData(color: cs.onPrimaryContainer, size: 20),
                  child: Center(child: icon!),
                ),
              ),
              const SizedBox(width: Gap.l),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DefaultTextStyle.merge(
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: destructive ? cs.error : cs.onSurface,
                    ),
                    child: title,
                  ),
                  if (description != null)
                    DefaultTextStyle.merge(
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                      child: description!,
                    ),
                ],
              ),
            ),
            ?action,
          ],
        ),
      ),
    );
  }
}

class CategoryGroup extends StatelessWidget {
  const CategoryGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return ClipRRect(
      borderRadius: br(Radius_.lg),
      child: Column(
        spacing: 2,
        children: [
          for (final c in children)
            Material(color: cs.surfaceContainerHigh, child: c),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.small = false});
  final String text;
  final bool small;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Gap.md, bottom: Gap.sm),
    child: Text(
      tr(text),
      style: (small ? context.tt.titleSmall : context.tt.titleMedium)?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class UnreadDot extends StatelessWidget {
  const UnreadDot({super.key, this.count = 0});
  final int count;
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    if (count > 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: cs.error,
          borderRadius: br(Radius_.md),
        ),
        child: Text(
          '$count',
          style: TextStyle(
            color: cs.onError,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: cs.onSurface, shape: BoxShape.circle),
    );
  }
}

class BadgeIcon extends StatelessWidget {
  const BadgeIcon({super.key, required this.name, this.size = 22});
  final String name;
  final double size;
  @override
  Widget build(BuildContext context) =>
      SvgPicture.asset('assets/badges/$name.svg', width: size, height: size);
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.cs.surfaceContainerHigh,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Wordmark(width: 160),
          const SizedBox(height: 24),
          const SizedBox(width: 160, child: LinearProgressIndicator()),
        ],
      ),
    ),
  );
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String body, {
  String action = 'Confirm',
}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr(title)),
      content: Text(tr(body)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: Text(tr('Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          child: Text(tr(action)),
        ),
      ],
    ),
  );
  return res ?? false;
}

Future<String?> promptText(
  BuildContext context,
  String title, {
  String? label,
  String? initial,
  String action = 'OK',
}) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr(title)),
      content: TextField(
        controller: ctl,
        autofocus: true,
        decoration: InputDecoration(
          labelText: label == null ? null : tr(label),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: Text(tr('Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, ctl.text.trim()),
          child: Text(tr(action)),
        ),
      ],
    ),
  );
}
