import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../api/client_store.dart';
import '../../core/css_colour.dart';
import '../../core/links.dart';
import '../../router.dart';
import '../../state/server_ordering.dart';
import '../../theme/tokens.dart';
import '../widgets.dart';
import 'app_dialog.dart';
import '../../core/i18n.dart';

String inviteLink(BuildContext context, String id) {
  final host = context.read<ClientStore>().host;
  return host == null || host == dawnchatHost ? '$inviteShortenerUrl$id' : context.fullHref('/invite/$id');
}

Future<void> showCreateInvite(BuildContext context, String channelId) {
  final store = context.read<ClientStore>();
  final future = store.api.post('/channels/$channelId/invites').then((r) => (r as Map)['_id'] as String);
  String? link;
  return showAppDialog<void>(
    context,
    title: tr('Create Invite'),
    content: FutureBuilder<String>(
      future: future,
      builder: (c, snap) {
        if (snap.hasError) return Text(errorText(snap.error!), style: TextStyle(color: c.cs.error));
        if (!snap.hasData) return Text(tr('Generating invite…'));
        link = inviteLink(context, snap.data!);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Here is your new invite code:'),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(child: SelectableText(link!, style: const TextStyle(fontFamily: 'monospace', fontSize: 22))),
            ),
          ],
        );
      },
    ),
    actions: [
      DlgAction(tr('OK')),
      DlgAction(tr('Copy Link'), onPressed: () async {
        if (link != null) await Clipboard.setData(ClipboardData(text: link!));
        return false;
      }),
    ],
  );
}

Future<void> showCreateChannel(BuildContext context, String serverId, {String? categoryId, void Function(Json channel)? onCreated}) {
  final store = context.read<ClientStore>();
  final name = TextEditingController();
  var type = 'Text';
  return showAppDialog<void>(
    context,
    title: tr('Create channel'),
    content: StatefulBuilder(
      builder: (c, set) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(controller: name, maxLength: 32, autofocus: true, decoration: InputDecoration(labelText: tr('Channel Name'))),
          RadioGroup<String>(
            groupValue: type,
            onChanged: (v) => set(() => type = v ?? 'Text'),
            child: Column(
              children: [
                RadioListTile<String>(value: 'Text', title: Text(tr('Text Channel'))),
                RadioListTile<String>(value: 'Voice', title: Text(tr('Voice Channel'))),
              ],
            ),
          ),
        ],
      ),
    ),
    actions: [
      DlgAction(tr('Close')),
      DlgAction(tr('Create'), onPressed: () async {
        if (name.text.trim().isEmpty) return false;
        final ch = ((await store.api.post('/servers/$serverId/channels', {'type': type, 'name': name.text.trim()})) as Map).cast<String, dynamic>();
        store.channels[ch['_id']] = ch;
        final server = store.servers[serverId];
        final list = (server?['channels'] as List?) ?? [];
        if (!list.contains(ch['_id'])) list.add(ch['_id']);
        server?['channels'] = list;
        if (categoryId != null && categoryId != 'default') {
          final cats = (((server?['categories'] as List?) ?? const []).cast<Map>()).map((c) => c.cast<String, dynamic>()).toList();
          final updated = [
            for (final cat in cats)
              {
                ...cat,
                'channels': [
                  ...(cat['channels'] as List).where((id) => id != ch['_id']),
                  if (cat['id'] == categoryId) ch['_id'],
                ],
              },
          ];
          await store.api.patch('/servers/$serverId', {'categories': updated});
          server?['categories'] = updated;
        }
        store.refresh();
        if (onCreated != null) {
          onCreated(ch);
        } else if (context.mounted) {
          context.goPath('/server/$serverId/channel/${ch['_id']}');
        }
        return null;
      }),
    ],
  );
}

Future<void> _saveCategories(ClientStore store, String serverId, List<Map<String, dynamic>> categories) async {
  await store.api.patch('/servers/$serverId', {'categories': categories});
  store.servers[serverId]?['categories'] = categories;
  store.refresh();
}

List<Map<String, dynamic>> _cats(ClientStore store, String serverId) =>
    [for (final c in ((store.servers[serverId]?['categories'] as List?) ?? const []).cast<Map>()) c.cast<String, dynamic>()];

Future<void> showCreateCategory(BuildContext context, String serverId) {
  final store = context.read<ClientStore>();
  final name = TextEditingController();
  return showAppDialog<void>(
    context,
    title: tr('Create a new category'),
    content: TextField(controller: name, maxLength: 32, autofocus: true, decoration: InputDecoration(labelText: tr('Name'))),
    actions: [
      DlgAction(tr('Close')),
      DlgAction(tr('Create'), onPressed: () async {
        if (name.text.trim().isEmpty) return false;
        await _saveCategories(store, serverId, [
          ..._cats(store, serverId),
          {'id': newUlid(), 'title': name.text.trim(), 'channels': <String>[]},
        ]);
        return null;
      }),
    ],
  );
}

Future<void> showDeleteCategory(BuildContext context, String serverId, String categoryId) {
  final store = context.read<ClientStore>();
  return showAppDialog<void>(
    context,
    title: tr('Delete category'),
    content: Text(tr("Once it's deleted, there's no going back.")),
    actions: [
      DlgAction(tr('Cancel')),
      DlgAction(tr('Delete'), destructive: true, onPressed: () async {
        await _saveCategories(store, serverId, _cats(store, serverId).where((c) => c['id'] != categoryId).toList());
        return null;
      }),
    ],
  );
}

Future<void> showEditCategory(BuildContext context, String serverId, String categoryId, String title) {
  final store = context.read<ClientStore>();
  final ctl = TextEditingController(text: title);
  return showAppDialog<void>(
    context,
    title: tr('Rename category'),
    content: TextField(controller: ctl, autofocus: true, decoration: InputDecoration(labelText: tr('New name'))),
    actions: [
      DlgAction(tr('Cancel')),
      DlgAction(tr('Rename'), onPressed: () async {
        await _saveCategories(store, serverId, [for (final c in _cats(store, serverId)) c['id'] == categoryId ? {...c, 'title': ctl.text} : c]);
        return null;
      }),
    ],
  );
}

Future<void> showLeaveServer(BuildContext context, String serverId) {
  final store = context.read<ClientStore>();
  var silent = false;
  final name = store.servers[serverId]?['name'] ?? '';
  return showAppDialog<void>(
    context,
    title: 'Leave $name?',
    content: StatefulBuilder(
      builder: (c, set) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr("You won't be able to rejoin unless you are re-invited.")),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: silent,
            onChanged: (v) => set(() => silent = v ?? false),
            title: Text(tr("Don't notify others that you've left")),
          ),
        ],
      ),
    ),
    actions: [
      DlgAction(tr('Cancel')),
      DlgAction(tr('Leave'), destructive: true, onPressed: () async {
        await store.api.delete('/servers/$serverId?leave_silently=$silent');
        store.servers.remove(serverId);
        store.channels.removeWhere((_, ch) => ch['server'] == serverId);
        store.refresh();
        if (context.mounted) context.goPath('/app');
        return null;
      }),
    ],
  );
}

Future<void> showEditFolder(BuildContext context, ServerFolder folder) {
  final store = context.read<ClientStore>();
  final ctl = TextEditingController(text: folder.name);
  String? colour = folder.colour;
  const swatches = ['#ef5350', '#ff7043', '#ffa726', '#ffee58', '#66bb6a', '#26a69a', '#29b6f6', '#5c6bc0', '#ab47bc', '#ec407a', '#8d6e63', '#78909c'];
  return showAppDialog<void>(
    context,
    title: tr('Edit folder'),
    content: StatefulBuilder(
      builder: (c, set) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(controller: ctl, decoration: InputDecoration(labelText: tr('Name'))),
          const SizedBox(height: Gap.lg),
          Text(tr('Folder colour'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(height: Gap.s),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              InkWell(
                onTap: () => set(() => colour = null),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.cs.outline, width: colour == null ? 3 : 1)),
                  child: const Icon(Icons.format_color_reset, size: 16),
                ),
              ),
              for (final s in swatches)
                InkWell(
                  onTap: () => set(() => colour = s),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: parseCssColour(s), shape: BoxShape.circle, border: Border.all(color: c.cs.onSurface, width: colour == s ? 3 : 0)),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
    actions: [
      DlgAction(tr('Cancel')),
      DlgAction(tr('Save'), onPressed: () async {
        store.ordering.editFolder(folder.id, name: ctl.text, colour: colour ?? '');
        store.refresh();
        return null;
      }),
    ],
  );
}

Future<void> showCreateOrJoinServer(BuildContext context) => showAppDialog<void>(
  context,
  title: 'Create or join a server',
  content: Text(tr('Would you like to create a new server or join an existing one?')),
  actions: [
    DlgAction(tr('Create'), onPressed: () async {
      Future.microtask(() {
        if (context.mounted) showCreateServer(context);
      });
      return null;
    }),
    DlgAction(tr('Join'), onPressed: () async {
      Future.microtask(() {
        if (context.mounted) showJoinServer(context);
      });
      return null;
    }),
  ],
);

Future<void> showCreateGroupOrServer(BuildContext context) => showAppDialog<void>(
  context,
  title: tr('Create a group or server'),
  content: Text(tr('Would you like to create a new group or server?')),
  actions: [
    DlgAction('Group', onPressed: () async {
      Future.microtask(() {
        if (context.mounted) showCreateGroup(context);
      });
      return null;
    }),
    DlgAction(tr('Server'), onPressed: () async {
      Future.microtask(() {
        if (context.mounted) showCreateServer(context);
      });
      return null;
    }),
  ],
);

Future<void> showCreateServer(BuildContext context) {
  final store = context.read<ClientStore>();
  final name = TextEditingController();
  return showAppDialog<void>(
    context,
    title: tr('Create server'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(
            text: 'By creating this server, you agree to the ',
            children: [
              WidgetSpan(
                child: InkWell(onTap: () => openUrl(acceptableUseUrl), child: Text('Acceptable Use Policy', style: TextStyle(color: context.cs.primary))),
              ),
              const TextSpan(text: '.'),
            ],
          ),
        ),
        TextField(controller: name, maxLength: 32, autofocus: true, decoration: InputDecoration(labelText: tr('Server Name'))),
      ],
    ),
    actions: [
      DlgAction(tr('Close')),
      DlgAction(tr('Create'), onPressed: () async {
        if (name.text.trim().isEmpty) return false;
        final res = await store.createServer(name.text.trim());
        final server = (res['server'] as Map).cast<String, dynamic>();
        store.servers[server['_id']] = server;
        for (final c in ((res['channels'] as List?) ?? const [])) {
          store.channels[c['_id']] = (c as Map).cast<String, dynamic>();
        }
        store.refresh();
        Future.microtask(() {
          if (context.mounted) context.goPath('/server/${server['_id']}');
        });
        return null;
      }),
    ],
  );
}

final _inviteRe = RegExp(r'(?:invite|stt\.gg)/([a-z0-9]+)', caseSensitive: false);

Future<void> showJoinServer(BuildContext context) {
  final store = context.read<ClientStore>();
  final ctl = TextEditingController();
  return showAppDialog<void>(
    context,
    title: tr('Join a server'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('Use a code or invite link')),
        TextField(controller: ctl, autofocus: true, decoration: InputDecoration(labelText: tr('Code'), hintText: 'stt.gg/wVEJDGVs')),
      ],
    ),
    actions: [
      DlgAction(tr('Close')),
      DlgAction(tr('Join'), onPressed: () async {
        var code = ctl.text.trim();
        if (code.isEmpty) return false;
        final m = _inviteRe.firstMatch(code);
        if (m != null) code = m.group(1)!;
        final res = await store.joinInvite(code);
        if (res['type'] == 'Server') {
          final id = (res['server'] as Map)['_id'];
          Future.microtask(() {
            if (context.mounted) context.goPath('/server/$id');
          });
        }
        return null;
      }),
    ],
  );
}

Future<void> showCreateGroup(BuildContext context) {
  final store = context.read<ClientStore>();
  final name = TextEditingController();
  final selected = <String>{};
  var filter = '';
  return showAppDialog<void>(
    context,
    title: tr('Create a new group'),
    maxWidth: 420,
    content: StatefulBuilder(
      builder: (c, set) {
        final users = store.friends.where((u) => store.displayName(u['_id'] as String).toLowerCase().contains(filter.toLowerCase())).toList()
          ..sort((a, b) => store.displayName(a['_id'] as String).toLowerCase().compareTo(store.displayName(b['_id'] as String).toLowerCase()));
        return SizedBox(
          width: 420,
          height: 380,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: name, maxLength: 32, decoration: InputDecoration(labelText: tr('Group Name'))),
              Text(tr('Select members to add'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
              TextField(decoration: InputDecoration(hintText: tr('Search for users...')), onChanged: (v) => set(() => filter = v)),
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
      DlgAction(tr('Create'), onPressed: () async {
        if (name.text.trim().isEmpty) return false;
        final g = ((await store.api.post('/channels/create', {'name': name.text.trim(), 'users': selected.toList()})) as Map).cast<String, dynamic>();
        store.channels[g['_id']] = g;
        store.refresh();
        Future.microtask(() {
          if (context.mounted) context.goPath('/channel/${g['_id']}');
        });
        return null;
      }),
    ],
  );
}
