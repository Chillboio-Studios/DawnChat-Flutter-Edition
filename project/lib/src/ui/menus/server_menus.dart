import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/client_store.dart';
import '../../api/permissions.dart';
import '../../core/links.dart';
import '../../router.dart';
import '../../state/server_ordering.dart';
import '../modals/channel_modals.dart';
import '../modals/member_modals.dart';
import '../modals/message_modals.dart';
import '../modals/server_modals.dart';
import '../settings/channel_settings.dart';
import '../settings/server_settings.dart';
import '../widgets.dart';
import 'context_menu.dart';
import 'notification_menu.dart';
import '../../core/i18n.dart';

bool channelUnread(ClientStore store, String id) => store.isUnread(id);

bool serverUnread(ClientStore store, String serverId) => store
    .channelsOfServer(serverId)
    .any((c) => store.isUnread(c['_id'] as String));

Future<void> markServerRead(ClientStore store, String serverId) async {
  for (final c in store.channelsOfServer(serverId)) {
    final id = c['_id'] as String;
    final last = c['last_message_id'] as String?;
    if (last != null && store.isUnread(id)) await store.ack(id, last);
  }
}

List<MenuItem> serverMenu(BuildContext context, String serverId) {
  final store = context.read<ClientStore>();
  final settings = store.settings;
  final server = store.servers[serverId];
  if (server == null) return const [];
  final isOwner = server['owner'] == store.userId;
  final folders = store.ordering.folders();
  final inFolder = store.ordering.folderOf(serverId);
  final channels = store.channelsOfServer(serverId);
  final inviteChannel = channels
      .where((c) => store.can(c['_id'] as String, Perm.inviteOthers))
      .firstOrNull;
  final canIdentity =
      store.canInServer(serverId, Perm.changeNickname) ||
      store.canInServer(serverId, Perm.changeAvatar);
  final canSettings =
      isOwner ||
      [
        Perm.assignRoles,
        Perm.banMembers,
        Perm.kickMembers,
        Perm.manageChannel,
        Perm.manageCustomisation,
        Perm.manageNicknames,
        Perm.managePermissions,
        Perm.manageRole,
        Perm.manageServer,
        Perm.manageWebhooks,
      ].any((p) => store.canInServer(serverId, p));
  final level = settings.notifFor('server', serverId) ?? 'mention';

  Widget radio(bool on) => Builder(
    builder: (c) => Icon(
      on ? Icons.radio_button_checked : Icons.radio_button_unchecked,
      size: 20,
      color: Theme.of(c).colorScheme.onSurface,
    ),
  );
  void setLevel(String v) {
    settings.setNotif('server', serverId, v);
    store.refresh();
  }

  final mute = notificationMenu(context, store, 'server', serverId).first;

  return [
    if (serverUnread(store, serverId)) ...[
      MenuItem.button(
        tr('Mark as read'),
        icon: Icons.mark_chat_read_outlined,
        onTap: () => markServerRead(store, serverId),
      ),
      const MenuItem.divider(),
    ],
    mute,
    MenuItem.sub(
      tr('Add to folder'),
      icon: Icons.folder_outlined,
      onTap: () {
        store.ordering.createFolder('New Folder', [serverId]);
        store.refresh();
      },
      children: [
        for (final f in folders)
          MenuItem.button(
            f.name.isEmpty ? 'Unnamed folder' : f.name,
            onTap: () {
              store.ordering.addToFolder(f.id, serverId);
              store.refresh();
            },
          ),
        MenuItem.button(
          tr('New folder'),
          icon: Icons.create_new_folder_outlined,
          onTap: () {
            store.ordering.createFolder('New Folder', [serverId]);
            store.refresh();
          },
        ),
      ],
    ),
    if (inFolder != null)
      MenuItem.button(
        tr('Remove from folder'),
        icon: Icons.folder_off_outlined,
        onTap: () {
          store.ordering.removeFromFolder(serverId);
          store.refresh();
        },
      ),
    const MenuItem.divider(),
    MenuItem.sub(
      tr('Notifications'),
      icon: Icons.notifications_outlined,
      children: [
        MenuItem.button(
          tr('All Messages'),
          icon: Icons.notifications_active_outlined,
          trailing: radio(level == 'all'),
          onTap: () => setLevel('all'),
        ),
        MenuItem.button(
          tr('Mentions Only'),
          icon: Icons.alternate_email,
          trailing: radio(level == 'mention'),
          onTap: () => setLevel('mention'),
        ),
        MenuItem.button(
          tr('None'),
          icon: Icons.notifications_off_outlined,
          trailing: radio(level == 'none'),
          onTap: () => setLevel('none'),
        ),
      ],
    ),
    const MenuItem.divider(),
    if (inviteChannel != null)
      MenuItem.button(
        tr('Create invite'),
        icon: Icons.person_add_outlined,
        onTap: () => showCreateInvite(context, inviteChannel['_id'] as String),
      ),
    if (canIdentity)
      MenuItem.button(
        tr('Edit your identity'),
        icon: Icons.face,
        onTap: () => showServerIdentity(context, serverId, store.userId!),
      ),
    if (canSettings)
      MenuItem.button(
        tr('Open server settings'),
        icon: Icons.settings_outlined,
        onTap: () => showServerSettings(context, serverId),
      ),
    if (inviteChannel != null || canIdentity || canSettings)
      const MenuItem.divider(),
    MenuItem.button(
      tr('Server info'),
      icon: Icons.info_outline,
      onTap: () => showServerInfo(context, serverId),
    ),
    MenuItem.button(
      tr('Report server'),
      icon: Icons.report_outlined,
      destructive: true,
      onTap: () => showReportDialog(context, type: 'Server', id: serverId),
    ),
    if (!isOwner)
      MenuItem.button(
        tr('Leave server'),
        icon: Icons.logout,
        destructive: true,
        onTap: () => showLeaveServer(context, serverId),
      ),
    if (store.isAdmin && settings.copyId) const MenuItem.divider(),
    if (store.isAdmin)
      MenuItem.button(
        tr('Admin Panel'),
        icon: Icons.shield_outlined,
        onTap: () => openUrl(adminInspectUrl('server', serverId)),
      ),
    if (settings.copyId)
      MenuItem.button(
        tr('Copy server ID'),
        icon: Icons.badge_outlined,
        onTap: () => copyText(context, serverId),
      ),
  ];
}

List<MenuItem> channelMenu(BuildContext context, Json channel) {
  final store = context.read<ClientStore>();
  final settings = store.settings;
  final id = channel['_id'] as String;
  final sid = channel['server'] as String?;
  final type = channel['channel_type'];
  final unread = store.isUnread(id);
  final canInvite = store.can(id, Perm.inviteOthers);
  final canManageServerChannels =
      sid != null && store.canInServer(sid, Perm.manageChannel);
  final canManage = store.can(id, Perm.manageChannel);

  String? categoryOf() {
    for (final c
        in ((store.servers[sid]?['categories'] as List?) ?? const [])
            .cast<Map>()) {
      if ((c['channels'] as List).contains(id)) return c['id'] as String;
    }
    return null;
  }

  return [
    if (unread || canInvite) ...[
      if (unread)
        MenuItem.button(
          tr('Mark as read'),
          icon: Icons.mark_chat_read_outlined,
          onTap: () {
            final last = channel['last_message_id'] as String?;
            if (last != null) store.ack(id, last);
          },
        ),
      if (canInvite)
        MenuItem.button(
          tr('Create invite'),
          icon: Icons.group_add_outlined,
          onTap: () => showCreateInvite(context, id),
        ),
      const MenuItem.divider(),
    ],
    ...notificationMenu(context, store, 'channel', id),
    const MenuItem.divider(),
    if (canManageServerChannels) ...[
      MenuItem.button(
        tr('Create channel'),
        icon: Icons.library_add_outlined,
        onTap: () => showCreateChannel(context, sid, categoryId: categoryOf()),
      ),
      MenuItem.button(
        tr('Create category'),
        icon: Icons.library_add_outlined,
        onTap: () => showCreateCategory(context, sid),
      ),
    ],
    if (canManage) ...[
      MenuItem.button(
        tr('Open channel settings'),
        icon: Icons.settings_outlined,
        onTap: () => showChannelSettings(context, id),
      ),
      MenuItem.button(
        type == 'Group' ? 'Leave group' : 'Delete channel',
        icon: type == 'Group' ? Icons.logout : Icons.delete_outline,
        destructive: true,
        onTap: () => showDeleteChannel(context, channel),
      ),
    ],
    if (canManageServerChannels || canManage) const MenuItem.divider(),
    if (store.isAdmin)
      MenuItem.button(
        tr('Admin Panel'),
        icon: Icons.shield_outlined,
        onTap: () => openUrl(adminInspectUrl('channel', id)),
      ),
    MenuItem.button(
      tr('Copy link'),
      icon: Icons.share_outlined,
      onTap: () => copyText(
        context,
        context.fullHref('${sid != null ? '/server/$sid' : ''}/channel/$id'),
      ),
    ),
    if (settings.copyId)
      MenuItem.button(
        tr('Copy channel ID'),
        icon: Icons.badge_outlined,
        onTap: () => copyText(context, id),
      ),
  ];
}

List<MenuItem> categoryMenu(
  BuildContext context,
  String serverId,
  Map<String, dynamic> category,
) {
  final store = context.read<ClientStore>();
  final settings = store.settings;
  final channelIds = (category['channels'] as List).cast<String>();
  final unread = channelIds.any(store.isUnread);
  final canManage = store.canInServer(serverId, Perm.manageChannel);
  // The 'default' bucket is synthetic — it can't be renamed, deleted, or
  // referenced by id, but it can still be marked read and added to.
  final isDefault = category['id'] == 'default';
  return [
    if (unread) ...[
      MenuItem.button(
        tr('Mark as read'),
        icon: Icons.mark_chat_read_outlined,
        onTap: () {
          for (final cid in channelIds) {
            final last = store.channels[cid]?['last_message_id'] as String?;
            if (last != null && store.isUnread(cid)) store.ack(cid, last);
          }
        },
      ),
      const MenuItem.divider(),
    ],
    if (canManage) ...[
      MenuItem.button(
        tr('Create channel'),
        icon: Icons.library_add_outlined,
        onTap: () => showCreateChannel(
          context,
          serverId,
          categoryId: category['id'] as String,
        ),
      ),
      MenuItem.button(
        tr('Create category'),
        icon: Icons.library_add_outlined,
        onTap: () => showCreateCategory(context, serverId),
      ),
      if (!isDefault)
        MenuItem.button(
          tr('Rename category'),
          icon: Icons.edit_outlined,
          onTap: () => showEditCategory(
            context,
            serverId,
            category['id'] as String,
            category['title'] as String? ?? '',
          ),
        ),
      if (!isDefault)
        MenuItem.button(
          tr('Delete category'),
          icon: Icons.delete_outline,
          destructive: true,
          onTap: () =>
              showDeleteCategory(context, serverId, category['id'] as String),
        ),
    ],
    if (!isDefault && settings.copyId) ...[
      const MenuItem.divider(),
      MenuItem.button(
        tr('Copy category ID'),
        icon: Icons.badge_outlined,
        onTap: () => copyText(context, category['id'] as String),
      ),
    ],
  ];
}

List<MenuItem> folderMenu(BuildContext context, ServerFolder folder) {
  final store = context.read<ClientStore>();
  return [
    MenuItem.button(
      tr('Edit folder'),
      icon: Icons.drive_file_rename_outline,
      onTap: () => showEditFolder(context, folder),
    ),
    const MenuItem.divider(),
    MenuItem.button(
      tr('Delete folder'),
      icon: Icons.delete_outline,
      destructive: true,
      onTap: () {
        store.ordering.deleteFolder(folder.id);
        store.refresh();
      },
    ),
  ];
}

List<MenuItem> serverSidebarMenu(BuildContext context, String serverId) {
  final store = context.read<ClientStore>();
  if (!store.canInServer(serverId, Perm.manageChannel)) return const [];
  return [
    MenuItem.button(
      tr('Create channel'),
      icon: Icons.library_add_outlined,
      onTap: () => showCreateChannel(context, serverId),
    ),
    MenuItem.button(
      tr('Create category'),
      icon: Icons.library_add_outlined,
      onTap: () => showCreateCategory(context, serverId),
    ),
  ];
}
