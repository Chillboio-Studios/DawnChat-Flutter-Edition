import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/client_store.dart';
import '../../api/permissions.dart';
import '../../theme/tokens.dart';
import '../messaging/markdown_view.dart';
import '../net_image.dart';
import '../settings/server_settings.dart';
import '../widgets.dart';
import 'app_dialog.dart';
import 'member_modals.dart';
import 'message_modals.dart';
import '../../core/i18n.dart';

/// Large emoji preview — port of the web client's `EmojiPreviewModal`.
Future<void> showEmojiPreview(
  BuildContext context, {
  required String name,
  required String url,
}) {
  return showAppDialog<void>(
    context,
    title: ':$name:',
    content: Center(
      child: NetImage(url, width: 128, height: 128, fit: BoxFit.contain),
    ),
    maxWidth: 240,
  );
}

/// Server info dialog — port of the web client's `ServerInfoModal`.
Future<void> showServerInfo(BuildContext context, String serverId) {
  final store = context.read<ClientStore>();
  final server = store.servers[serverId];
  if (server == null) return Future.value();
  final canSettings =
      store.canInServer(serverId, Perm.manageServer) ||
      store.canInServer(serverId, Perm.manageCustomisation) ||
      store.canInServer(serverId, Perm.manageRole) ||
      store.canInServer(serverId, Perm.managePermissions);
  return showAppDialog<void>(
    context,
    title: store.channelName({'name': server['name']}),
    content: SelectionArea(
      child: RichContent(
        (server['description'] as String?) ?? '',
        serverId: serverId,
      ),
    ),
    actions: [
      if (canSettings)
        DlgAction(
          tr('Settings'),
          onPressed: () async {
            if (context.mounted) await showServerSettings(context, serverId);
            return null;
          },
        ),
      DlgAction(
        tr('Edit Identity'),
        onPressed: () async {
          if (context.mounted && store.userId != null) {
            await showServerIdentity(context, serverId, store.userId!);
          }
          return null;
        },
      ),
      DlgAction(
        tr('Report'),
        onPressed: () async {
          if (context.mounted) {
            await showReportDialog(context, type: 'Server', id: serverId);
          }
          return null;
        },
      ),
      DlgAction(tr('Close')),
    ],
  );
}

Future<void> showChannelInfo(BuildContext context, Json channel) {
  final type = channel['channel_type'];
  return showAppDialog<void>(
    context,
    title: type == 'TextChannel' ? '#${channel['name']}' : '${channel['name']}',
    content: SelectionArea(
      child: RichContent(
        (channel['description'] as String?) ?? '',
        serverId: channel['server'] as String?,
      ),
    ),
  );
}

Future<void> showAddMembersToGroup(BuildContext context, Json group) {
  final store = context.read<ClientStore>();
  final selected = <String>{};
  var filter = '';
  return showAppDialog<void>(
    context,
    title: tr('Add friends to group'),
    maxWidth: 420,
    content: StatefulBuilder(
      builder: (c, set) {
        final recipients = ((group['recipients'] as List?) ?? const [])
            .cast<String>();
        final users =
            store.friends
                .where((u) => !recipients.contains(u['_id']))
                .where(
                  (u) => store
                      .displayName(u['_id'] as String)
                      .toLowerCase()
                      .contains(filter.toLowerCase()),
                )
                .toList()
              ..sort(
                (a, b) => store
                    .displayName(a['_id'] as String)
                    .toLowerCase()
                    .compareTo(
                      store.displayName(b['_id'] as String).toLowerCase(),
                    ),
              );
        return SizedBox(
          width: 420,
          height: 360,
          child: Column(
            children: [
              TextField(
                decoration: InputDecoration(
                  hintText: tr('Search for users...'),
                ),
                onChanged: (v) => set(() => filter = v),
              ),
              const SizedBox(height: Gap.md),
              Expanded(
                child: ListView(
                  children: [
                    for (final u in users)
                      CheckboxListTile(
                        value: selected.contains(u['_id']),
                        onChanged: (v) => set(
                          () => v == true
                              ? selected.add(u['_id'] as String)
                              : selected.remove(u['_id']),
                        ),
                        secondary: UserAvatar(
                          userId: u['_id'] as String,
                          size: 32,
                        ),
                        title: Text(store.displayName(u['_id'] as String)),
                        controlAffinity: ListTileControlAffinity.trailing,
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
    actions: [
      DlgAction(tr('Close')),
      DlgAction(
        tr('Add'),
        onPressed: () async {
          for (final u in selected) {
            await store.api.put('/channels/${group['_id']}/recipients/$u');
          }
          return null;
        },
      ),
    ],
  );
}
