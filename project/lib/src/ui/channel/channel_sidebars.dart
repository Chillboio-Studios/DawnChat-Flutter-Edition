import 'package:flutter/material.dart';
import '../net_image.dart';
import 'package:provider/provider.dart';

import '../../api/client_store.dart';
import '../../api/permissions.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../menus/context_menu.dart';
import '../menus/user_menu.dart';
import '../messaging/message_tile.dart';
import '../../router.dart';
import '../widgets.dart';

String userStatusText(ClientStore store, String userId) {
  final u = store.user(userId);
  final text = (u?['status'] as Map?)?['text'] as String?;
  if (text != null && text.isNotEmpty) return text;
  if (u?['online'] != true) return 'Offline';
  return switch ((u?['status'] as Map?)?['presence']) {
    'Busy' => 'Busy',
    'Focus' => 'Focus',
    'Idle' => 'Idle',
    'Invisible' => 'Offline',
    _ => 'Online',
  };
}

/// Right sidebar listing a server's or group's members.
class MemberSidebar extends StatelessWidget {
  const MemberSidebar({super.key, required this.channel});
  final Json channel;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final cs = context.cs;
    final serverId = channel['server'] as String?;
    final isGroup = channel['channel_type'] == 'Group';

    final items = <Widget>[];
    Widget title(String text, {Widget? lead, double top = 12}) => Padding(
      padding: EdgeInsets.fromLTRB(14, top, 0, 0),
      child: DefaultTextStyle.merge(
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface),
        child: Row(spacing: 6, children: [?lead, Text(text)]),
      ),
    );

    if (isGroup) {
      final ids = ((channel['recipients'] as List?) ?? const []).cast<String>().toList()
        ..sort((a, b) => store.displayName(a).toLowerCase().compareTo(store.displayName(b).toLowerCase()));
      items.add(title('${ids.length} members'));
      for (final u in ids) {
        items.add(MemberRow(userId: u, group: channel));
      }
    } else if (serverId != null) {
      final server = store.servers[serverId] ?? const {};
      final roles = (server['roles'] as Map?)?.cast<String, dynamic>() ?? const {};
      final hoisted = roles.entries.where((e) => e.value['hoist'] == true).toList()
        ..sort((a, b) => ((a.value['rank'] as num?) ?? 0).compareTo((b.value['rank'] as num?) ?? 0));
      final byRole = <String, List<(String, String)>>{'default': [], 'offline': [], for (final h in hoisted) h.key: []};
      final restricted = ((channel['default_permissions'] != null) || ((channel['role_permissions'] as Map?)?.isNotEmpty ?? false));
      final members = store.members[serverId] ?? const {};
      for (final entry in members.entries) {
        final userId = entry.key;
        final m = entry.value;
        if (restricted) {
          final p = channelPermissions(channel: channel, server: server, member: m, userId: userId);
          if ((p & Perm.viewChannel) != Perm.viewChannel) continue;
        }
        final name = (m['nickname'] as String?) ?? store.displayName(userId);
        if (store.user(userId)?['online'] != true) {
          byRole['offline']!.add((userId, name));
          continue;
        }
        final mine = ((m['roles'] as List?) ?? const []).cast<String>();
        String? bucket;
        for (final h in hoisted) {
          if (mine.contains(h.key)) {
            bucket = h.key;
            break;
          }
        }
        byRole[bucket ?? 'default']!.add((userId, name));
      }
      final sections = <(String, String, String?)>[
        for (final h in hoisted) (h.key, h.value['name'] as String? ?? '', h.value['icon'] != null ? store.api.fileUrl('icons', h.value['icon'] as Map?, width: 32) : null),
        ('default', 'Online', null),
        ('offline', 'Offline', null),
      ];
      var online = 0;
      for (final s in sections) {
        if (s.$1 != 'offline') online += byRole[s.$1]!.length;
      }
      final large = ((server['approximate_member_count'] as num?) ?? 0) > 1000;
      if (!large) {
        items.add(
          title('$online members online', lead: const _Dot(), top: 12),
        );
      }
      for (final s in sections) {
        final list = byRole[s.$1]!..sort((a, b) => a.$2.toLowerCase().compareTo(b.$2.toLowerCase()));
        if (list.isEmpty) continue;
        items.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 28, 0, 0),
            child: DefaultTextStyle.merge(
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface),
              child: Row(
                spacing: 6,
                children: [
                  if (s.$3 != null) ClipRRect(borderRadius: br(Radius_.sm), child: NetImage(s.$3!, width: 16, height: 16, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox(width: 16, height: 16))),
                  Text(s.$2),
                  Text(' – ${list.length}'),
                ],
              ),
            ),
          ),
        );
        for (final (userId, _) in list) {
          items.add(MemberRow(userId: userId, serverId: serverId, channelId: channel['_id'] as String));
        }
      }
    }

    return SizedBox(
      width: Layout.channelSidebarWidth,
      child: Padding(
        padding: const EdgeInsets.only(right: Gap.md),
        child: ListView(children: items),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();
  @override
  Widget build(BuildContext context) => Container(width: 8, height: 8, decoration: BoxDecoration(color: StatusColors.of('Online'), shape: BoxShape.circle));
}

class MemberRow extends StatelessWidget {
  const MemberRow({super.key, required this.userId, this.serverId, this.group, this.channelId});
  final String userId;
  final String? serverId, channelId;
  final Json? group;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final cs = context.cs;
    final online = store.user(userId)?['online'] == true;
    final member = serverId == null ? null : store.members[serverId]?[userId];
    final timeout = member?['timeout'] as String?;
    final timedOut = timeout != null && (DateTime.tryParse(timeout)?.isAfter(DateTime.now()) ?? false);
    final canModerate = serverId != null && channelId != null && store.can(channelId!, Perm.timeoutMembers);
    final status = userStatusText(store, userId);
    final colour = store.roleColour(userId, serverId);
    final name = store.displayName(userId, server: serverId);
    void card() => openUserCard(context, userId, serverId: serverId);

    return GestureDetector(
      onSecondaryTapUp: (d) => showContextMenu(context, d.globalPosition, userMenu(context, userId, serverId: serverId)),
      onLongPressStart: (d) => showContextMenu(context, d.globalPosition, userMenu(context, userId, serverId: serverId)),
      child: MenuButton(
        height: 42,
        muted: !online,
        active: online,
        onTap: card,
        leading: Opacity(opacity: timedOut && canModerate ? .5 : 1, child: UserAvatar(userId: userId, size: 32, showStatus: true)),
        title: Row(
          spacing: 4,
          children: [
            Flexible(child: Text(name, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: colour))),
            if (timedOut && canModerate) Tooltip(message: 'Timed out until ${DateTime.parse(timeout).toLocal()}', child: Icon(Icons.timer_off, size: 14, color: cs.outline)),
          ],
        ),
        subtitle: Tooltip(message: status, child: Text(status, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ),
    );
  }
}

/// Search results / pinned messages sidebar.
class SearchSidebar extends StatefulWidget {
  const SearchSidebar({super.key, required this.channel, this.query, this.pinned = false});
  final Json channel;
  final String? query;
  final bool pinned;
  @override
  State<SearchSidebar> createState() => _SearchSidebarState();
}

class _SearchSidebarState extends State<SearchSidebar> {
  String sort = 'Latest';
  Future<List<Json>>? _future;
  String _key = '';

  @override
  Widget build(BuildContext context) {
    final store = context.read<ClientStore>();
    final cs = context.cs;
    final id = widget.channel['_id'] as String;
    final key = '$id|${widget.query}|${widget.pinned}|$sort';
    if (key != _key) {
      _key = key;
      _future = store.searchMessages(id, query: widget.query, pinned: widget.pinned, sort: widget.pinned ? 'Latest' : sort);
    }
    final sid = widget.channel['server'] as String?;
    return Column(
      children: [
        if (!widget.pinned)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.md),
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [ButtonSegment(value: 'Relevance', label: Text('Relevance')), ButtonSegment(value: 'Latest', label: Text('Latest')), ButtonSegment(value: 'Oldest', label: Text('Oldest'))],
              selected: {sort},
              onSelectionChanged: (s) => setState(() => sort = s.first),
            ),
          ),
        Expanded(
          child: FutureBuilder<List<Json>>(
            future: _future,
            builder: (c, snap) {
              if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
              if (snap.hasError) return Center(child: Text(errorText(snap.error!), style: TextStyle(color: cs.error)));
              final msgs = snap.data ?? const [];
              if (msgs.isEmpty) return Center(child: Text(widget.pinned ? 'No pinned messages' : 'No results', style: TextStyle(color: cs.outline)));
              return ListView(
                children: [
                  for (final m in msgs)
                    MessageTile(
                      key: ValueKey(m['_id']),
                      message: m,
                      serverId: sid,
                      isLink: MessageLink.link,
                      onTapLink: () => context.goPath('${sid != null ? '/server/$sid' : ''}/channel/$id/${m['_id']}'),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
