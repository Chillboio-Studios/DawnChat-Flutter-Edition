import 'package:flutter/material.dart';
import '../net_image.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/client_store.dart';
import '../../core/links.dart';
import '../../router.dart';
import '../../theme/tokens.dart';
import '../settings/server_settings.dart';
import '../settings/channel_settings.dart';
import '../voice/voice_ui.dart';
import '../widgets.dart';
import '../menus/context_menu.dart';
import '../menus/server_menus.dart' as menus;
import 'interface_shell.dart';
import '../../core/i18n.dart';

class OrderedCategory {
  OrderedCategory({
    required this.id,
    required this.title,
    required this.channelIds,
  });

  final String id;
  String title;
  List<String> channelIds;

  Map<String, dynamic> toMap() => <String, dynamic>{
    'id': id,
    'title': title,
    'channels': List<String>.from(channelIds),
  };
}

/// Port of `orderedCategories` from `ordering.ts`.
List<OrderedCategory> orderedCategories(
  List<dynamic>? categories,
  List<String> knownChannelIds,
) {
  final known = knownChannelIds.toSet();
  final uncategorised = knownChannelIds.toSet();

  final ordered = <OrderedCategory>[];
  for (final raw in categories ?? const <dynamic>[]) {
    if (raw is! Map) continue;
    final id = (raw['id'] as String?) ?? 'default';
    final title = (raw['title'] as String?) ?? '';
    final channels = ((raw['channels'] as List?) ?? const <dynamic>[])
        .whereType<String>()
        .where(known.contains)
        .toList();
    for (final cid in channels) {
      uncategorised.remove(cid);
    }
    if (id != 'default' || channels.any(known.contains)) {
      ordered.add(
        OrderedCategory(
          id: id,
          title: title,
          channelIds: channels,
        ),
      );
    }
  }

  final uncategorisedIds = uncategorised.toList();
  final defaultCategory = ordered.where((c) => c.id == 'default').firstOrNull;
  if (defaultCategory != null) {
    defaultCategory.channelIds = [
      ...defaultCategory.channelIds,
      ...uncategorisedIds,
    ];
  } else {
    ordered.insert(
      0,
      OrderedCategory(
        id: 'default',
        title: 'Default',
        channelIds: uncategorisedIds,
      ),
    );
  }

  return ordered;
}

/// Port of `applyChannelOrdering` from `ordering.ts`.
List<String> applyChannelOrdering(
  List<String> channelIds,
  List<String> visibleIds,
  List<String> reorderedIds,
) {
  final newOrdering = <String>[];
  final visible = visibleIds.toSet();
  final remaining = <String>[...channelIds];

  for (final orderedId in reorderedIds) {
    final index = remaining.indexOf(orderedId);

    if (index == -1) {
      newOrdering.add(orderedId);
      continue;
    }

    final leading = remaining.sublist(0, index);
    remaining.removeRange(0, index);

    newOrdering.addAll(leading.where((id) => !visible.contains(id)));

    // invariant: remaining[0] == orderedId
    newOrdering.add(remaining.removeAt(0));

    remaining.insertAll(0, leading.where(visible.contains));
  }

  return <String>[
    ...newOrdering,
    ...remaining.where((id) => !visible.contains(id)),
  ];
}

Future<void> saveServerCategories(
  ClientStore store,
  String serverId,
  List<OrderedCategory> categories,
) async {
  final server = store.servers[serverId];
  if (server == null) return;
  final payload = <Map<String, dynamic>>[
    for (final cat in categories)
      if (cat.id != 'default' || cat.channelIds.isNotEmpty)
        <String, dynamic>{
          'id': cat.id,
          'title': cat.title,
          'channels': List<String>.from(cat.channelIds),
        },
  ];
  final allOrderedIds = <String>[
    for (final cat in categories) ...cat.channelIds,
  ];
  final existingChannels = ((server['channels'] as List?) ?? const <dynamic>[])
      .whereType<String>()
      .toList();
  for (final id in existingChannels) {
    if (!allOrderedIds.contains(id)) allOrderedIds.add(id);
  }
  server['categories'] = payload;
  server['channels'] = allOrderedIds;
  store.refresh();
  await store.api.patch('/servers/$serverId', {'categories': payload});
}

class SidebarPanel extends StatelessWidget {
  const SidebarPanel({super.key, required this.target});
  final NavTarget target;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Container(
      color: cs.surfaceContainerHigh,
      child: target.serverId != null
          ? ServerSidebar(serverId: target.serverId!, channelId: target.channelId)
          : HomeSidebar(channelId: target.channelId),
    );
  }
}

Future<void> showNotificationOptions(BuildContext context, String kind, String id) {
  final store = context.read<ClientStore>();
  final s = store.settings;
  return showDialog<void>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) {
        final level = s.notifFor(kind, id);
        final muted = s.isMuted(kind, id);
        void apply(VoidCallback fn) {
          fn();
          store.refresh();
          set(() {});
        }

        Widget mute(String label, Duration? d) => ListTile(
              dense: true,
              title: Text(tr(label)),
              onTap: () => apply(() => s.setMute(kind, id, d == null ? -1 : DateTime.now().add(d).millisecondsSinceEpoch)),
            );

        return AlertDialog(
          title: const Text('Notification options'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              RadioGroup<String?>(
                groupValue: level,
                onChanged: (v) => apply(() => s.setNotif(kind, id, v)),
                child: Column(children: [
                  RadioListTile<String?>(title: Text(tr('Default')), value: null),
                  RadioListTile<String?>(title: Text(tr('All Messages')), value: 'all'),
                  RadioListTile<String?>(title: Text(tr('Mentions Only')), value: 'mention'),
                  RadioListTile<String?>(title: Text(tr('None')), value: 'none'),
                ]),
              ),
              const Divider(),
              if (muted)
                ListTile(dense: true, title: Text(tr('Unmute')), leading: const Icon(Icons.notifications_active_outlined), onTap: () => apply(() => s.setMute(kind, id, null)))
              else ...[
                mute('Mute for 15 minutes', const Duration(minutes: 15)),
                mute('Mute for 1 hour', const Duration(hours: 1)),
                mute('Mute for 8 hours', const Duration(hours: 8)),
                mute('Mute for 24 hours', const Duration(hours: 24)),
                mute('Mute until I turn it back on', null),
              ],
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Done')))],
        );
      },
    ),
  );
}

Future<void> channelMenu(BuildContext context, Map<String, dynamic> c) async {
  final store = context.read<ClientStore>();
  final id = c['_id'] as String;
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (s) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: Text(tr('Channel Settings')),
            onTap: () => Navigator.pop(s, 'settings'),
          ),
          ListTile(
            leading: const Icon(Icons.mark_chat_read_outlined),
            title: Text(tr('Mark as read')),
            onTap: () => Navigator.pop(s, 'read'),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notification options'),
            onTap: () => Navigator.pop(s, 'notif'),
          ),
          if (store.settings.copyId)
            ListTile(
              leading: const Icon(Icons.copy),
              title: Text(tr('Copy ID')),
              onTap: () => Navigator.pop(s, 'copy'),
            ),
          if (store.settings.adminPanel)
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: const Text('Open in admin panel'),
              onTap: () => Navigator.pop(s, 'admin'),
            ),
        ],
      ),
    ),
  );
  if (!context.mounted || choice == null) return;
  switch (choice) {
    case 'settings':
      showChannelSettings(context, id);
    case 'read':
      final last = c['last_message_id'] as String?;
      if (last != null) await store.ack(id, last);
    case 'notif':
      await showNotificationOptions(context, 'channel', id);
    case 'copy':
      await copyText(context, id);
    case 'admin':
      await openUrl(adminInspectUrl('channel', id));
  }
}

class _Category extends StatelessWidget {
  const _Category(this.title, {this.trailing});
  final String title;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.xl - 5, Gap.lg, Gap.md),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.cs.onSurfaceVariant,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class HomeSidebar extends StatelessWidget {
  const HomeSidebar({super.key, this.channelId});
  final String? channelId;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final path = relPath(GoRouterState.of(context).uri.path);
    final pending = store.incomingRequests.length;
    final saved = store.channels.values
        .where((c) => c['channel_type'] == 'SavedMessages')
        .firstOrNull;

    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        Container(
          height: 48,
          margin: const EdgeInsets.all(Gap.md).copyWith(left: Gap.lg),
          alignment: Alignment.centerLeft,
          child: Text(
            tr('Conversations'),
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
        ),
        MenuButton(
          leading: const Icon(Icons.home_outlined),
          title: Text(tr('Home')),
          selected: path == '/app' || path == '/',
          onTap: () => context.goPath('/app'),
        ),
        const SizedBox(height: 5),
        MenuButton(
          leading: const Icon(Icons.group_outlined),
          title: Text(tr('Friends')),
          selected: path == '/friends',
          trailing: pending > 0
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Gap.md,
                    vertical: Gap.sm,
                  ),
                  decoration: BoxDecoration(
                    color: context.cs.error,
                    borderRadius: br(Radius_.md),
                  ),
                  child: Text(
                    '$pending requests',
                    style: TextStyle(
                      color: context.cs.onError,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : null,
          onTap: () => context.goPath('/friends'),
        ),
        const SizedBox(height: 5),
        MenuButton(
          leading: const Icon(Icons.sticky_note_2_outlined),
          title: Text(tr('Saved Notes')),
          selected: saved != null && saved['_id'] == channelId,
          onTap: () async {
            if (saved != null) {
              context.goPath('/channel/${saved['_id']}');
            } else {
              final c = await store.openDm(store.userId!);
              if (context.mounted) context.goPath('/channel/${c['_id']}');
            }
          },
        ),
        _Category(
          'Direct Messages',
          trailing: InkWell(
            onTap: () => _createGroup(context),
            child: const Icon(Icons.add, size: 20),
          ),
        ),
        for (final c in store.dmList)
          _DmEntry(channel: c, active: c['_id'] == channelId),
      ],
    );
  }

  Future<void> _createGroup(BuildContext context) async {
    final store = context.read<ClientStore>();
    final name = await promptText(
      context,
      'Create a group',
      label: tr('Group Name'),
      action: tr('Create'),
    );
    if (name == null || name.isEmpty) return;
    try {
      final c = ((await store.api.post('/channels/create', {
        'name': name,
        'users': <String>[],
      })) as Map).cast<String, dynamic>();
      store.channels[c['_id']] = c;
      if (context.mounted) context.goPath('/channel/${c['_id']}');
    } catch (e) {
      if (context.mounted) showSnack(context, errorText(e));
    }
  }
}

class _DmEntry extends StatelessWidget {
  const _DmEntry({required this.channel, required this.active});
  final Map<String, dynamic> channel;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final id = channel['_id'] as String;
    final isGroup = channel['channel_type'] == 'Group';
    final other = (channel['recipients'] as List?)?.cast<String>().firstWhere(
      (r) => r != store.userId,
      orElse: () => '',
    );
    final unread = store.isUnread(id);
    final u = store.user(other);
    final status =
        (u?['status'] as Map?)?['text'] as String? ??
        (u?['online'] == true
            ? ((u?['status'] as Map?)?['presence'] ?? 'Online') as String
            : 'Offline');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: MenuButton(
        height: 48,
        selected: active,
        active: unread,
        leading: isGroup
            ? IconAvatar(
                url: store.api.fileUrl(
                  'icons',
                  channel['icon'] as Map?,
                  width: 64,
                ),
                name: store.channelName(channel),
              )
            : UserAvatar(userId: other, size: 32, showStatus: true),
        title: Text(store.channelName(channel)),
        subtitle: Text(
          isGroup
              ? '${(channel['recipients'] as List).length} Members'
              : status,
        ),
        trailing: unread && !active
            ? UnreadDot(count: store.mentionCount(id))
            : null,
        onTap: () => context.goPath('/channel/$id'),
        onLongPress: () => channelMenu(context, channel),
      ),
    );
  }
}

class ServerSidebar extends StatelessWidget {
  const ServerSidebar({super.key, required this.serverId, this.channelId});
  final String serverId;
  final String? channelId;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final cs = context.cs;
    final server = store.servers[serverId];
    if (server == null) return const SizedBox.shrink();

    final all = store.channelsOfServer(serverId);
    final categories = ((server['categories'] as List?) ?? []).cast<Map>();
    final categorised = {
      for (final c in categories) ...((c['channels'] as List).cast<String>()),
    };
    final loose = all.where((c) => !categorised.contains(c['_id'])).toList();
    final banner = store.api.fileUrl(
      'banners',
      server['banner'] as Map?,
      width: 480,
    );

    Widget channelTile(Map<String, dynamic> c) {
      final id = c['_id'] as String;
      final isVoice = c['channel_type'] == 'VoiceChannel' || c['voice'] != null;
      final unread = store.isUnread(id);
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: GestureDetector(
              onSecondaryTapUp: (details) => showContextMenu(context, details.globalPosition, menus.channelMenu(context, c)),
              onLongPressStart: (details) => showContextMenu(context, details.globalPosition, menus.channelMenu(context, c)),
              child: MenuButton(
              height: 36,
              selected: id == channelId,
              active: unread,
              leading: Icon(
                isVoice ? Icons.headset_mic_outlined : Icons.tag,
                size: 20,
              ),
              title: Text(c['name'] as String? ?? 'Unnamed'),
              trailing: unread && id != channelId
                  ? UnreadDot(count: store.mentionCount(id))
                  : null,
              onTap: () => context.goPath('/server/$serverId/channel/$id'),
              ),
            ),
          ),
          if (isVoice) VoiceChannelPreview(channelId: id, serverId: serverId),
        ],
      );
    }

    return Column(
      children: [
        InkWell(
          onTap: () => _serverMenu(context, server),
          child: Container(
            height: banner != null ? 120 : 48,
            width: double.infinity,
            decoration: banner != null
                ? BoxDecoration(
                    image: DecorationImage(
                      image: netImageProvider(banner),
                      fit: BoxFit.cover,
                    ),
                  )
                : null,
            alignment: Alignment.bottomLeft,
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.lg,
              vertical: 12,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    server['name'] as String? ?? '',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: banner != null ? Colors.white : cs.onSurface,
                      shadows: banner != null
                          ? const [Shadow(blurRadius: 4)]
                          : null,
                    ),
                  ),
                ),
                Icon(
                  Icons.expand_more,
                  color: banner != null ? Colors.white : cs.onSurface,
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 8),
            children: [
              for (final c in loose) channelTile(c),
              for (final cat in categories) ...[
                GestureDetector(
                  onSecondaryTapUp: (details) => showContextMenu(context, details.globalPosition, menus.categoryMenu(context, serverId, cat.cast<String, dynamic>())),
                  onLongPressStart: (details) => showContextMenu(context, details.globalPosition, menus.categoryMenu(context, serverId, cat.cast<String, dynamic>())),
                  child: _Category((cat['title'] as String? ?? '').toUpperCase()),
                ),
                for (final id in (cat['channels'] as List).cast<String>())
                  if (store.channels[id] != null)
                    channelTile(store.channels[id]!),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _serverMenu(
    BuildContext context,
    Map<String, dynamic> server,
  ) async {
    final store = context.read<ClientStore>();
    final isOwner = server['owner'] == store.userId;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Server info'),
              onTap: () => Navigator.pop(c, 'info'),
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Server settings'),
              onTap: () => Navigator.pop(c, 'settings'),
            ),
            ListTile(
              leading: const Icon(Icons.add),
              title: Text(tr('Create channel')),
              onTap: () => Navigator.pop(c, 'channel'),
            ),
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('Notification options'),
              onTap: () => Navigator.pop(c, 'notif'),
            ),
            if (store.settings.copyId)
              ListTile(
                leading: const Icon(Icons.copy),
                title: Text(tr('Copy ID')),
                onTap: () => Navigator.pop(c, 'copy'),
              ),
            ListTile(
              leading: Icon(Icons.logout, color: c.cs.error),
              title: Text(
                isOwner ? 'Delete server' : 'Leave server',
                style: TextStyle(color: c.cs.error),
              ),
              onTap: () => Navigator.pop(c, 'leave'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || choice == null) return;
    switch (choice) {
      case 'info':
        showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(server['name'] as String? ?? ''),
            content: Text(
              (server['description'] as String?) ?? 'No description.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: Text(tr('Close')),
              ),
            ],
          ),
        );
      case 'settings':
        showServerSettings(context, serverId);
      case 'notif':
        await showNotificationOptions(context, 'server', serverId);
      case 'channel':
        final name = await promptText(
          context,
          tr('Create channel'),
          label: tr('Channel Name'),
          action: tr('Create'),
        );
        if (name == null || name.isEmpty || !context.mounted) return;
        try {
          final ch = ((await store.api.post('/servers/$serverId/channels', {
            'type': 'Text',
            'name': name,
          })) as Map).cast<String, dynamic>();
          store.channels[ch['_id']] = ch;
          (server['channels'] as List).add(ch['_id']);
          store.refresh();
        } catch (e) {
          if (context.mounted) showSnack(context, errorText(e));
        }
      case 'copy':
        await copyText(context, serverId);
      case 'leave':
        if (await confirm(
          context,
          isOwner ? 'Delete server?' : 'Leave server?',
          isOwner
              ? 'This cannot be undone.'
              : 'You will need an invite to rejoin.',
          action: isOwner ? 'Delete' : 'Leave',
        )) {
          await store.leaveServer(serverId);
          if (context.mounted) context.goPath('/app');
        }
    }
  }
}
