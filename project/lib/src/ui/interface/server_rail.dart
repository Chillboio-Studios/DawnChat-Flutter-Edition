import 'package:flutter/material.dart';
import 'dart:ui' show PointerDeviceKind;
import 'package:provider/provider.dart';

import '../../api/client_store.dart';
import '../../core/css_colour.dart';
import '../../core/links.dart';
import '../../router.dart';
import '../../state/server_ordering.dart';
import '../../state/settings_store.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../voice/voice_manager.dart';
import '../menus/context_menu.dart';
import '../menus/server_menus.dart';
import '../menus/user_menu.dart';
import '../modals/app_dialog.dart';
import '../modals/server_modals.dart';
import '../settings/settings_page.dart';
import '../widgets.dart';
import 'interface_shell.dart' show NavTarget;
import '../../core/i18n.dart';

String lastServerPath(SettingsStore s, String serverId) => s.raw<String>('layout.server.$serverId') ?? '/server/$serverId';

/// Left-most rail: home, user, unread DMs, servers/folders, create/join, discover and settings.
class ServerRail extends StatefulWidget {
  const ServerRail({super.key, required this.target});
  final NavTarget target;
  @override
  State<ServerRail> createState() => _ServerRailState();
}

class _DragPayload {
  const _DragPayload(this.id, {this.parent});
  final String id;
  final String? parent;
}

class _ServerRailState extends State<ServerRail> {
  String? hoverTarget;
  String? hoverMode; // fold | before | after

  ClientStore get store => context.read<ClientStore>();

  void _drop(_DragPayload moved, String targetId, String mode, {String? targetParent}) {
    final ord = store.ordering;
    final entries = ord.orderedEntries(store.servers.keys);
    final currentOrder = entries.map((e) => e.id).toList();

    if (moved.id == targetId) return;

    if (mode == 'fold' && targetParent == null) {
      final target = entries.where((e) => e.id == targetId).firstOrNull;
      if (target == null || (target.isFolder && moved.id == target.id)) return;
      final ids = currentOrder.where((id) => id != moved.id).toList();
      if (target.isFolder) {
        ord.addToFolder(target.id, moved.id);
      } else {
        final folderId = ord.createFolder('New Folder', [targetId, moved.id]);
        final at = ids.indexOf(targetId);
        if (at != -1) ids[at] = folderId;
      }
      ord.setServerOrder(ids);
      store.refresh();
      return;
    }

    // before / after: figure the "before" id among the destination list
    final ids = currentOrder.where((id) => id != moved.id).toList();
    if (targetParent != null) {
      final folder = ord.folders().where((f) => f.id == targetParent).firstOrNull;
      if (folder == null) return;
      String? before;
      if (mode == 'before') {
        before = targetId;
      } else {
        final idx = folder.servers.indexOf(targetId);
        before = idx >= 0 && idx + 1 < folder.servers.length ? folder.servers[idx + 1] : null;
      }
      ord.placeInFolder(targetParent, moved.id, before == moved.id ? null : before);
      ord.setServerOrder(ids);
      store.refresh();
      return;
    }

    if (ord.folderOf(moved.id) != null) ord.removeFromFolder(moved.id);
    var at = ids.indexOf(targetId);
    if (at == -1) at = ids.length;
    if (mode == 'after') at += 1;
    ids.insert(at.clamp(0, ids.length), moved.id);
    ord.setServerOrder(ids);
    store.refresh();
  }

  Widget _wrapDnD({required String id, String? parent, required Widget child, required double height, required Widget Function(bool dragging) feedback}) {
    final isTouchOnly = Theme.of(context).platform == TargetPlatform.android || Theme.of(context).platform == TargetPlatform.iOS;
    final phone = screenClassOf(MediaQuery.sizeOf(context)) == ScreenClass.phone;
    if (phone && isTouchOnly) return child;
    return DragTarget<_DragPayload>(
      onWillAcceptWithDetails: (d) => d.data.id != id,
      onMove: (d) {
        final box = context.findRenderObject() as RenderBox?;
        final key = _keys[id]?.currentContext?.findRenderObject() as RenderBox?;
        if (box == null || key == null) return;
        final local = key.globalToLocal(d.offset + const Offset(21, 21));
        final h = key.size.height;
        final mode = local.dy < h * .25 ? 'before' : local.dy > h * .75 ? 'after' : 'fold';
        if (hoverTarget != id || hoverMode != mode) setState(() {
          hoverTarget = id;
          hoverMode = mode;
        });
      },
      onLeave: (_) {
        if (hoverTarget == id) setState(() => hoverTarget = null);
      },
      onAcceptWithDetails: (d) {
        final mode = hoverMode ?? 'after';
        setState(() => hoverTarget = null);
        _drop(d.data, id, mode, targetParent: parent);
      },
      builder: (c, cand, rej) => LongPressDraggable<_DragPayload>(
        data: _DragPayload(id, parent: parent),
        delay: const Duration(milliseconds: 250),
        feedback: Material(type: MaterialType.transparency, child: Opacity(opacity: .85, child: feedback(true))),
        childWhenDragging: Opacity(opacity: .35, child: child),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            child,
            if (hoverTarget == id && hoverMode == 'before') Positioned(top: -2, left: 6, right: 6, child: Container(height: 4, decoration: BoxDecoration(color: context.cs.primary, borderRadius: BorderRadius.circular(2)))),
            if (hoverTarget == id && hoverMode == 'after') Positioned(bottom: -2, left: 6, right: 6, child: Container(height: 4, decoration: BoxDecoration(color: context.cs.primary, borderRadius: BorderRadius.circular(2)))),
            if (hoverTarget == id && hoverMode == 'fold')
              Positioned.fill(child: IgnorePointer(child: Center(child: Container(width: 50, height: 50, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: context.cs.primary, width: 2)))))),
          ],
        ),
      ),
    );
  }

  final _keys = <String, GlobalKey>{};
  GlobalKey _key(String id) => _keys[id] ??= GlobalKey();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final settings = context.watch<SettingsStore>();
    final cs = context.cs;
    final target = widget.target;
    final entries = store.ordering.orderedEntries(store.servers.keys);
    final dms = store.dmList.where((c) => store.isUnread(c['_id'] as String)).toList();
    final pending = store.incomingRequests.length;
    final isDefaultInstance = store.host == null || store.host == dawnchatHost;

    Widget entry({required Widget child, bool selected = false, bool alert = false, VoidCallback? onTap, String? tooltip, Widget? tooltipRich, GestureTapUpCallback? onSecondary, GlobalKey? key}) {
      return Tooltip(
        message: tooltipRich == null ? (tooltip ?? '') : null,
        richMessage: tooltipRich == null ? null : WidgetSpan(child: tooltipRich),
        waitDuration: const Duration(milliseconds: 400),
        preferBelow: false,
        child: _RailHover(
          builder: (hover) => SizedBox(
            key: key,
            width: 56,
            height: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  left: 0,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 4,
                    height: selected ? 32 : (hover ? 16 : (alert ? 8 : 0)),
                    decoration: BoxDecoration(color: cs.onSurface, borderRadius: const BorderRadius.horizontal(right: Radius.circular(4))),
                  ),
                ),
                GestureDetector(
                  onSecondaryTapUp: onSecondary,
                  onLongPressStart: onSecondary == null ? null : (d) => onSecondary(TapUpDetails(kind: PointerDeviceKind.touch, globalPosition: d.globalPosition, localPosition: d.localPosition)),
                  child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: child),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget badge(Widget avatar, {int count = 0, bool unread = false, Widget? bottomRight}) => SizedBox(
      width: 42,
      height: 42,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          if (count > 0 || unread) Positioned(right: -4, top: -4, child: UnreadDot(count: count)),
          ?bottomRight,
        ],
      ),
    );

    Widget serverEntry(String serverId, {String? parent}) {
      final s = store.servers[serverId]!;
      final chs = store.channelsOfServer(serverId);
      final muted = settings.isMuted('server', serverId);
      final unread = chs.any((c) => store.isUnread(c['_id'] as String)) && !muted;
      final mentions = chs.fold<int>(0, (a, c) => a + store.mentionCount(c['_id'] as String));
      final voiceConnected = chs.any((c) => context.watch<VoiceManager>().channelId == c['_id']);
      final voiceActive = chs.any((c) => (store.voiceStates[c['_id']]?.isNotEmpty ?? false));
      final avatar = IconAvatar(url: store.api.fileUrl('icons', s['icon'] as Map?, width: 256), name: s['name'] as String? ?? '?', size: 42, square: false);
      final built = KeyedSubtree(
        key: _key(serverId),
        child: entry(
          selected: target.serverId == serverId,
          alert: unread,
          tooltipRich: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s['name'] as String? ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: cs.onInverseSurface)),
              if (muted) Text(tr('Muted'), style: TextStyle(fontSize: 12, color: cs.onInverseSurface.withValues(alpha: .7))),
            ],
          ),
          onTap: () => context.goPath(lastServerPath(settings, serverId)),
          onSecondary: (d) => showContextMenu(context, d.globalPosition, serverMenu(context, serverId)),
          child: badge(
            avatar,
            count: mentions,
            bottomRight: (voiceConnected || voiceActive)
                ? Positioned(
                    right: -3,
                    bottom: -3,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(color: cs.surfaceContainerHigh, shape: BoxShape.circle),
                      child: Icon(Icons.headset_mic, size: 12, color: voiceConnected ? cs.primary : cs.onSurfaceVariant),
                    ),
                  )
                : null,
          ),
        ),
      );
      return _wrapDnD(id: serverId, parent: parent, child: built, height: 56, feedback: (_) => avatar);
    }

    Widget folderPreview(RailEntry e) {
      final f = e.folder!;
      final colour = f.colour == null ? null : _tint(f.colour!, .3);
      final size = e.servers.length > 2 ? 13.0 : 16.0;
      return Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(color: colour ?? cs.primaryContainer, shape: BoxShape.circle),
        child: Wrap(
          alignment: WrapAlignment.center,
          runAlignment: WrapAlignment.center,
          spacing: 2,
          runSpacing: 2,
          children: [
            for (final id in e.servers.take(4))
              IconAvatar(url: store.api.fileUrl('icons', store.servers[id]?['icon'] as Map?, width: 128), name: store.servers[id]?['name'] as String? ?? '?', size: size, square: false),
          ],
        ),
      );
    }

    Widget folderEntry(RailEntry e) {
      final f = e.folder!;
      final collapsed = f.collapsed;
      final name = f.name.isEmpty ? 'Folder' : f.name;
      final mentions = e.servers.fold<int>(0, (a, sid) => a + store.channelsOfServer(sid).fold<int>(0, (b, c) => b + store.mentionCount(c['_id'] as String)));
      final unread = e.servers.any((sid) => !settings.isMuted('server', sid) && store.channelsOfServer(sid).any((c) => store.isUnread(c['_id'] as String)));
      final holdsSelected = e.servers.contains(target.serverId);
      final colour = f.colour == null ? null : parseColour(f.colour!);
      final head = KeyedSubtree(
        key: _key(e.id),
        child: entry(
          tooltip: name,
          selected: collapsed && holdsSelected,
          alert: collapsed && unread,
          onTap: () {
            store.ordering.toggleFolder(f.id);
            store.refresh();
          },
          onSecondary: (d) => showContextMenu(context, d.globalPosition, folderMenu(context, f)),
          child: badge(
            collapsed && e.servers.isNotEmpty
                ? folderPreview(e)
                : Container(width: 42, height: 42, decoration: BoxDecoration(color: cs.surfaceContainerHighest, shape: BoxShape.circle), child: Icon(Icons.folder_open, size: 24, color: colour ?? cs.onSurface)),
            count: collapsed ? mentions : 0,
          ),
        ),
      );
      return Container(
        decoration: collapsed
            ? null
            : BoxDecoration(color: colour != null ? _tint(f.colour!, .18) : cs.onSurface.withValues(alpha: .1), borderRadius: br(Radius_.lg)),
        padding: collapsed ? EdgeInsets.zero : const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _wrapDnD(id: e.id, child: head, height: 56, feedback: (_) => folderPreview(e)),
            if (!collapsed) for (final sid in e.servers) if (store.servers[sid] != null) serverEntry(sid, parent: f.id),
          ],
        ),
      );
    }

    return Container(
      width: 56 + 8,
      color: cs.surfaceContainerHigh,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
              children: [
                entry(
                  selected: target.serverId == null && !target.discover && target.channelId == null,
                  tooltip: pending > 0 ? 'You have $pending pending friend requests.' : 'Home',
                  onTap: () => context.goPath('/app'),
                  child: badge(
                    Container(width: 42, height: 42, decoration: BoxDecoration(color: cs.surfaceContainerHighest, shape: BoxShape.circle), child: Icon(Icons.home, color: cs.onSurface)),
                    count: pending,
                  ),
                ),
                Builder(
                  builder: (c) => entry(
                    tooltipRich: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(store.me?['username'] as String? ?? '', style: TextStyle(color: cs.onInverseSurface)),
                        Text(_presenceLabel(store), style: TextStyle(fontSize: 12, color: cs.onInverseSurface.withValues(alpha: .7))),
                      ],
                    ),
                    onTap: () {
                      final box = c.findRenderObject() as RenderBox;
                      final p = box.localToGlobal(Offset(box.size.width + 5, 0));
                      showContextMenu(c, p, _selfMenu(c));
                    },
                    child: SizedBox(width: 42, height: 42, child: UserAvatar(userId: store.userId, size: 42, showStatus: true)),
                  ),
                ),
                for (final c in dms.take(9))
                  entry(
                    tooltip: store.channelName(c),
                    onTap: () => context.goPath('/channel/${c['_id']}'),
                    onSecondary: (d) {
                      final other = ((c['recipients'] as List?) ?? const []).cast<String>().firstWhere((r) => r != store.userId, orElse: () => '');
                      showContextMenu(context, d.globalPosition, c['channel_type'] == 'DirectMessage' ? userMenu(context, other, channel: c) : channelMenu(context, c));
                    },
                    child: badge(
                      c['channel_type'] == 'Group'
                          ? IconAvatar(url: store.api.fileUrl('icons', c['icon'] as Map?, width: 256), name: store.channelName(c), size: 42, square: false)
                          : UserAvatar(userId: ((c['recipients'] as List).cast<String>().firstWhere((r) => r != store.userId, orElse: () => '')), size: 42),
                      count: store.mentionCount(c['_id'] as String),
                      unread: true,
                    ),
                  ),
                if (dms.length > 9)
                  entry(
                    onTap: () => context.goPath('/'),
                    child: Container(width: 42, height: 42, decoration: BoxDecoration(color: cs.surfaceContainerHighest, shape: BoxShape.circle), alignment: Alignment.center, child: Text('+${dms.length - 9}')),
                  ),
                Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12), color: cs.outlineVariant),
                for (final e in entries) e.isFolder ? folderEntry(e) : serverEntry(e.id),
                entry(
                  tooltip: 'Create or join a server',
                  onTap: () => showCreateOrJoinServer(context),
                  child: Container(width: 42, height: 42, decoration: BoxDecoration(color: cs.surfaceContainerHighest, shape: BoxShape.circle), child: Icon(Icons.add, color: cs.onSurface)),
                ),
                if (isDefaultInstance)
                  entry(
                    tooltip: 'Find new servers to join',
                    selected: target.discover,
                    onTap: () => context.goPath(settings.raw<String>('layout.discover') ?? '/discover'),
                    child: Container(width: 42, height: 42, decoration: BoxDecoration(color: cs.surfaceContainerHighest, shape: BoxShape.circle), child: Icon(Icons.explore, color: cs.onSurface)),
                  ),
              ],
            ),
          ),
          Container(height: 1, color: cs.outlineVariant.withValues(alpha: .0)),
          entry(
            tooltip: tr('Settings'),
            onTap: () => showSettings(context),
            child: Container(width: 42, height: 42, decoration: BoxDecoration(color: cs.surfaceContainerHighest, shape: BoxShape.circle), child: Icon(Icons.settings, color: cs.onSurface)),
          ),
        ],
      ),
    );
  }

  String _presenceLabel(ClientStore store) {
    final p = (store.me?['status'] as Map?)?['presence'] as String?;
    return switch (p) { 'Busy' => 'Do Not Disturb', 'Idle' => 'Idle', 'Focus' => 'Focus', 'Invisible' => 'Invisible', _ => 'Online' };
  }

  List<MenuItem> _selfMenu(BuildContext context) {
    final store = context.read<ClientStore>();
    final me = store.me ?? const {};
    final text = (me['status'] as Map?)?['text'] as String?;
    return [
      MenuItem.custom(
        InkWell(
          onTap: () {
            Navigator.of(context, rootNavigator: true).pop();
            showSettings(context);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            child: Row(
              spacing: 8,
              children: [
                UserAvatar(userId: store.userId, size: 32),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(store.displayName(store.userId), style: const TextStyle(fontSize: 14)),
                    Text('${me['username']}#${me['discriminator']}', style: TextStyle(fontSize: 12, color: context.cs.outline)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      const MenuItem.divider(),
      MenuItem.custom(_PresenceRow(label: tr('Online'), presence: 'Online', onTap: () => store.setStatus('Online', text: text))),
      MenuItem.custom(_PresenceRow(label: tr('Idle'), presence: 'Idle', onTap: () => store.setStatus('Idle', text: text))),
      MenuItem.custom(_PresenceRow(label: tr('Focus'), presence: 'Focus', hint: tr('Only mentions will notify you'), onTap: () => store.setStatus('Focus', text: text))),
      MenuItem.custom(_PresenceRow(label: tr('Do Not Disturb'), presence: 'Busy', hint: tr('You will not receive any notifications'), onTap: () => store.setStatus('Busy', text: text))),
      MenuItem.custom(_PresenceRow(label: tr('Invisible'), presence: 'Invisible', onTap: () => store.setStatus('Invisible', text: text))),
      const MenuItem.divider(),
      if (text == null || text.isEmpty)
        MenuItem.button(tr('Add status text'), icon: Icons.edit_note, onTap: () => showCustomStatus(context))
      else ...[
        MenuItem.button(text, icon: Icons.edit_note, capitalise: false, onTap: () => showCustomStatus(context)),
        MenuItem.button(tr('Clear status'), icon: Icons.delete_outline, onTap: () => store.setStatus((me['status'] as Map?)?['presence'] as String? ?? 'Online', clearText: true)),
      ],
      if (store.settings.copyId) MenuItem.button(tr('Copy user ID'), icon: Icons.contact_page_outlined, onTap: () => copyText(context, store.userId!)),
    ];
  }
}

class _PresenceRow extends StatelessWidget {
  const _PresenceRow({required this.label, required this.presence, required this.onTap, this.hint});
  final String label, presence;
  final String? hint;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () {
      Navigator.of(context, rootNavigator: true).pop();
      onTap();
    },
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
      child: Row(
        spacing: 8,
        children: [
          SizedBox(width: 16, child: Center(child: Container(width: 10, height: 10, decoration: BoxDecoration(color: StatusColors.of(presence == 'Invisible' ? null : presence), shape: BoxShape.circle, border: presence == 'Invisible' ? Border.all(color: context.cs.outline, width: 2) : null)))),
          Text(tr(label), style: const TextStyle(fontSize: 14)),
          if (hint != null) Tooltip(message: hint!, child: const Icon(Icons.info_outline, size: 12)),
        ],
      ),
    ),
  );
}

class _RailHover extends StatefulWidget {
  const _RailHover({required this.builder});
  final Widget Function(bool hover) builder;
  @override
  State<_RailHover> createState() => _RailHoverState();
}

class _RailHoverState extends State<_RailHover> {
  bool h = false;
  @override
  Widget build(BuildContext context) => MouseRegion(onEnter: (_) => setState(() => h = true), onExit: (_) => setState(() => h = false), child: widget.builder(h));
}

Color _tint(String colour, double amount) {
  final c = parseColour(colour) ?? Colors.grey;
  return c.withValues(alpha: amount);
}

Color? parseColour(String css) => parseCssColour(css);

Future<void> showCustomStatus(BuildContext context) {
  final store = context.read<ClientStore>();
  final ctl = TextEditingController(text: (store.me?['status'] as Map?)?['text'] as String? ?? '');
  return showAppDialog<void>(
    context,
    title: tr('Custom status'),
    content: TextField(controller: ctl, maxLength: 128, autofocus: true, decoration: InputDecoration(labelText: tr('Custom status'))),
    actions: [
      DlgAction(tr('Cancel')),
      DlgAction(tr('Save'), onPressed: () async {
        final presence = (store.me?['status'] as Map?)?['presence'] as String? ?? 'Online';
        await store.setStatus(presence, text: ctl.text.trim().isEmpty ? null : ctl.text.trim(), clearText: ctl.text.trim().isEmpty);
        return null;
      }),
    ],
  );
}
