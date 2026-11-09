import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/client_store.dart';
import '../../theme/tokens.dart';
import '../messaging/markdown_view.dart';
import '../widgets.dart';
import 'app_dialog.dart';
import '../../core/i18n.dart';

Future<void> showChannelInfo(BuildContext context, Json channel) {
  final type = channel['channel_type'];
  return showAppDialog<void>(
    context,
    title: type == 'TextChannel' ? '#${channel['name']}' : '${channel['name']}',
    content: SelectionArea(child: RichContent((channel['description'] as String?) ?? '', serverId: channel['server'] as String?)),
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
        final recipients = ((group['recipients'] as List?) ?? const []).cast<String>();
        final users =
            store.friends
                .where((u) => !recipients.contains(u['_id']))
                .where((u) => store.displayName(u['_id'] as String).toLowerCase().contains(filter.toLowerCase()))
                .toList()
              ..sort((a, b) => store.displayName(a['_id'] as String).toLowerCase().compareTo(store.displayName(b['_id'] as String).toLowerCase()));
        return SizedBox(
          width: 420,
          height: 360,
          child: Column(
            children: [
              TextField(decoration: InputDecoration(hintText: tr('Search for users...')), onChanged: (v) => set(() => filter = v)),
              const SizedBox(height: Gap.md),
              Expanded(
                child: ListView(
                  children: [
                    for (final u in users)
                      CheckboxListTile(
                        value: selected.contains(u['_id']),
                        onChanged: (v) => set(() => v == true ? selected.add(u['_id'] as String) : selected.remove(u['_id'])),
                        secondary: UserAvatar(userId: u['_id'] as String, size: 32),
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
      DlgAction(tr('Add'), onPressed: () async {
        for (final u in selected) {
          await store.api.put('/channels/${group['_id']}/recipients/$u');
        }
        return null;
      }),
    ],
  );
}
