import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/client_store.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../widgets.dart';
import '../../core/i18n.dart';

Future<void> showChannelSettings(BuildContext context, String channelId) {
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<ClientStore>(),
        child: ChannelSettingsPage(channelId: channelId),
      ),
    ),
  );
}

int _b(int n) => pow(2, n).toInt();
bool _has(int v, int bit) => (v ~/ bit) % 2 == 1;

final _perms = <(String, int)>[
  ('View Channel', _b(20)),
  ('Read Message History', _b(21)),
  ('Send Messages', _b(22)),
  ('Manage Messages', _b(23)),
  ('Manage Webhooks', _b(24)),
  ('Invite Others', _b(25)),
  ('Send Embeds', _b(26)),
  ('Upload Files', _b(27)),
  ('Masquerade', _b(28)),
  ('React', _b(29)),
  ('Connect', _b(30)),
  ('Speak', _b(31)),
  ('Video', _b(32)),
  ('Mute Members', _b(33)),
  ('Deafen Members', _b(34)),
  ('Move Members', _b(35)),
  ('Listen', _b(36)),
  ('Mention Everyone', _b(37)),
  ('Mention Roles', _b(38)),
];

class ChannelSettingsPage extends StatefulWidget {
  const ChannelSettingsPage({super.key, required this.channelId});
  final String channelId;
  @override
  State<ChannelSettingsPage> createState() => _ChannelSettingsPageState();
}

class _ChannelSettingsPageState extends State<ChannelSettingsPage> {
  String _page = 'overview';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final cs = context.cs;
    final c = store.channels[widget.channelId];
    if (c == null)
      return const Scaffold(body: Center(child: Text('Channel not found')));
    final phone =
        screenClassOf(MediaQuery.sizeOf(context)) == ScreenClass.phone;
    final isServer = c['server'] != null;
    final pages = [
      ('overview', 'Overview', Icons.info_outline),
      if (isServer) ('permissions', 'Permissions', Icons.lock_outline),
      if (isServer) ('webhooks', 'Webhooks', Icons.webhook_outlined),
    ];

    final nav = ListView(
      padding: const EdgeInsets.all(8),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton.filledTonal(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            store.channelName(c),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
        ),
        for (final p in pages)
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: br(Radius_.xl)),
            selected: _page == p.$1,
            selectedTileColor: cs.secondaryContainer,
            leading: Icon(p.$3),
            title: Text(tr(p.$2)),
            onTap: () => setState(() => _page = p.$1),
          ),
        const Divider(),
        ListTile(
          leading: Icon(Icons.delete_outline, color: cs.error),
          title: Text(
            tr(isServer ? 'Delete Channel' : 'Delete / Leave'),
            style: TextStyle(color: cs.error),
          ),
          onTap: () async {
            if (await confirm(
              context,
              'Delete channel?',
              'This cannot be undone.',
              action: tr('Delete'),
            )) {
              try {
                await store.api.delete('/channels/${widget.channelId}');
                store.channels.remove(widget.channelId);
                store.refresh();
                if (context.mounted) Navigator.pop(context);
              } catch (e) {
                if (context.mounted) showSnack(context, errorText(e));
              }
            }
          },
        ),
      ],
    );

    final body = Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: phone
            ? null
            : const BorderRadius.horizontal(left: Radius.circular(30)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          phone ? 12 : 32,
          phone ? 12 : 80,
          phone ? 12 : 32,
          80,
        ),
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 740),
            child: switch (_page) {
              'permissions' => _Permissions(channelId: widget.channelId),
              'webhooks' => _Webhooks(channelId: widget.channelId),
              _ => _Overview(channelId: widget.channelId),
            },
          ),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: cs.surfaceContainerHigh,
      appBar: phone
          ? AppBar(
              title: Text(pages.firstWhere((p) => p.$1 == _page).$2),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                if (pages.length > 1)
                  PopupMenuButton<String>(
                    onSelected: (v) => setState(() => _page = v),
                    itemBuilder: (_) => [
                      for (final p in pages)
                        PopupMenuItem(value: p.$1, child: Text(tr(p.$2))),
                    ],
                  ),
              ],
            )
          : null,
      body: SafeArea(
        child: phone
            ? body
            : Row(
                children: [
                  Expanded(
                    flex: 218,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: 230,
                          maxWidth: 300,
                        ),
                        child: nav,
                      ),
                    ),
                  ),
                  Expanded(flex: 800, child: body),
                ],
              ),
      ),
    );
  }
}

class _Overview extends StatefulWidget {
  const _Overview({required this.channelId});
  final String channelId;
  @override
  State<_Overview> createState() => _OverviewState();
}

class _OverviewState extends State<_Overview> {
  late final _name = TextEditingController(
    text:
        context.read<ClientStore>().channels[widget.channelId]?['name']
            as String?,
  );
  late final _desc = TextEditingController(
    text:
        context.read<ClientStore>().channels[widget.channelId]?['description']
            as String?,
  );
  late bool _nsfw =
      context.read<ClientStore>().channels[widget.channelId]?['nsfw'] == true;

  @override
  Widget build(BuildContext context) {
    final store = context.read<ClientStore>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _name,
          decoration: InputDecoration(labelText: tr('Channel Name')),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _desc,
          minLines: 3,
          maxLines: 8,
          decoration: InputDecoration(labelText: tr('Channel Description')),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Age-restricted (NSFW)'),
          value: _nsfw,
          onChanged: (v) => setState(() => _nsfw = v),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () async {
            try {
              await store.api.patch('/channels/${widget.channelId}', {
                'name': _name.text.trim(),
                'description': _desc.text,
                'nsfw': _nsfw,
              });
              if (context.mounted) showSnack(context, 'Saved');
            } catch (e) {
              if (context.mounted) showSnack(context, errorText(e));
            }
          },
          child: Text(tr('Save')),
        ),
      ],
    );
  }
}

class _Permissions extends StatefulWidget {
  const _Permissions({required this.channelId});
  final String channelId;
  @override
  State<_Permissions> createState() => _PermissionsState();
}

class _PermissionsState extends State<_Permissions> {
  int get _allow {
    final c = context.read<ClientStore>().channels[widget.channelId];
    final d = c?['default_permissions'] as Map?;
    return (d?['a'] as num?)?.toInt() ?? 0;
  }

  Future<void> _toggle(int bit, bool on) async {
    final store = context.read<ClientStore>();
    final next = on
        ? (_has(_allow, bit) ? _allow : _allow + bit)
        : (_has(_allow, bit) ? _allow - bit : _allow);
    try {
      await store.api.put('/channels/${widget.channelId}/permissions/default', {
        'permissions': {'allow': next, 'deny': 0},
      });
      store.channels[widget.channelId]!['default_permissions'] = {
        'a': next,
        'd': 0,
      };
      store.refresh();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final allow = _allow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Default permissions for everyone in this channel.'),
        const SizedBox(height: 12),
        CategoryGroup(
          children: [
            for (final p in _perms)
              CategoryButton(
                title: Text(tr(p.$1)),
                action: Switch(
                  value: _has(allow, p.$2),
                  onChanged: (v) => _toggle(p.$2, v),
                ),
                onTap: () => _toggle(p.$2, !_has(allow, p.$2)),
              ),
          ],
        ),
      ],
    );
  }
}

class _Webhooks extends StatefulWidget {
  const _Webhooks({required this.channelId});
  final String channelId;
  @override
  State<_Webhooks> createState() => _WebhooksState();
}

class _WebhooksState extends State<_Webhooks> {
  List<Map<String, dynamic>>? _list;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await context.read<ClientStore>().api.get(
        '/channels/${widget.channelId}/webhooks',
      ) as List;
      if (mounted)
        setState(
          () =>
              _list = r.map((e) => (e as Map).cast<String, dynamic>()).toList(),
        );
    } catch (_) {
      if (mounted) setState(() => _list = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<ClientStore>();
    final list = _list;
    if (list == null) return const Center(child: CircularProgressIndicator());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton.icon(
          icon: const Icon(Icons.add),
          label: Text(tr('Create Webhook')),
          onPressed: () async {
            final name = await promptText(
              context,
              tr('Create Webhook'),
              label: tr('Webhook Name'),
              action: tr('Create'),
            );
            if (name == null || name.isEmpty) return;
            try {
              await store.api.post('/channels/${widget.channelId}/webhooks', {
                'name': name,
              });
              _load();
            } catch (e) {
              if (context.mounted) showSnack(context, errorText(e));
            }
          },
        ),
        const SizedBox(height: 16),
        if (list.isEmpty)
          const Text('No webhooks.')
        else
          CategoryGroup(
            children: [
              for (final w in list)
                CategoryButton(
                  icon: const Icon(Icons.webhook_outlined),
                  title: Text(w['name'] as String? ?? 'Webhook'),
                  description: Text(w['id'] as String? ?? ''),
                  action: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (w['token'] != null)
                        IconButton(
                          icon: const Icon(Icons.copy),
                          tooltip: 'Copy URL',
                          onPressed: () => copyText(
                            context,
                            '${store.api.baseUrl}/webhooks/${w['id']}/${w['token']}',
                          ),
                        ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await store.api.delete('/webhooks/${w['id']}');
                          _load();
                        },
                      ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
