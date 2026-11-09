import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../net_image.dart';
import 'package:provider/provider.dart';

import '../../api/client_store.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../widgets.dart';
import '../../core/i18n.dart';

Future<void> showServerSettings(BuildContext context, String serverId) {
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<ClientStore>(),
        child: ServerSettingsPage(serverId: serverId),
      ),
    ),
  );
}

class ServerSettingsPage extends StatefulWidget {
  const ServerSettingsPage({super.key, required this.serverId});
  final String serverId;
  @override
  State<ServerSettingsPage> createState() => _ServerSettingsPageState();
}

class _ServerSettingsPageState extends State<ServerSettingsPage> {
  String _page = 'overview';

  static final _entries = [
    ('Server', [('overview', 'Overview', Icons.info_outline)]),
    ('Customisation', [('emojis', 'Emojis', Icons.emoji_emotions_outlined)]),
    (
      tr('User Management'),
      [
        ('members', 'Members', Icons.group_outlined),
        ('roles', 'Roles', Icons.badge_outlined),
        ('invites', 'Invites', Icons.link),
        ('bans', 'Bans', Icons.gavel),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final store = context.watch<ClientStore>();
    final server = store.servers[widget.serverId];
    if (server == null)
      return const Scaffold(body: Center(child: Text('Server not found')));
    final phone =
        screenClassOf(MediaQuery.sizeOf(context)) == ScreenClass.phone;

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
            server['name'] as String? ?? '',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
        ),
        for (final cat in _entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 4),
            child: Text(
              cat.$1.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: cs.outline,
              ),
            ),
          ),
          for (final e in cat.$2)
            ListTile(
              shape: RoundedRectangleBorder(borderRadius: br(Radius_.xl)),
              selected: _page == e.$1,
              selectedTileColor: cs.secondaryContainer,
              leading: Icon(e.$3),
              title: Text(tr(e.$2)),
              onTap: () => setState(() => _page = e.$1),
            ),
        ],
        const Divider(),
        ListTile(
          leading: Icon(Icons.delete_outline, color: cs.error),
          title: Text(tr('Delete Server'), style: TextStyle(color: cs.error)),
          onTap: () async {
            if (await confirm(
              context,
              'Delete server?',
              'This cannot be undone.',
              action: tr('Delete'),
            )) {
              await store.leaveServer(widget.serverId);
              if (context.mounted) Navigator.pop(context);
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
              'overview' => _Overview(serverId: widget.serverId),
              'emojis' => _Emojis(serverId: widget.serverId),
              'members' => _Members(serverId: widget.serverId),
              'roles' => _Roles(serverId: widget.serverId),
              'invites' => _Invites(serverId: widget.serverId),
              'bans' => _Bans(serverId: widget.serverId),
              _ => const SizedBox.shrink(),
            },
          ),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: cs.surfaceContainerHigh,
      appBar: phone
          ? AppBar(
              title: Text(
                _entries
                    .expand((c) => c.$2)
                    .firstWhere((e) => e.$1 == _page)
                    .$2,
              ),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                PopupMenuButton<String>(
                  onSelected: (v) => setState(() => _page = v),
                  itemBuilder: (_) => [
                    for (final c in _entries)
                      for (final e in c.$2)
                        PopupMenuItem(value: e.$1, child: Text(tr(e.$2))),
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

Future<void> _guard(BuildContext context, Future<void> Function() fn) async {
  try {
    await fn();
  } catch (e) {
    if (context.mounted) showSnack(context, errorText(e));
  }
}

class _Overview extends StatefulWidget {
  const _Overview({required this.serverId});
  final String serverId;
  @override
  State<_Overview> createState() => _OverviewState();
}

class _OverviewState extends State<_Overview> {
  late final _name = TextEditingController(
    text:
        context.read<ClientStore>().servers[widget.serverId]?['name']
            as String?,
  );
  late final _desc = TextEditingController(
    text:
        context.read<ClientStore>().servers[widget.serverId]?['description']
            as String?,
  );

  Future<void> _upload(String tag, String field) async {
    final store = context.read<ClientStore>();
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final f = res?.files.firstOrNull;
    if (f?.bytes == null) return;
    await _guard(context, () async {
      final id = await store.api.uploadFile(
        tag,
        f!.name,
        'image/${(f.extension ?? 'png').toLowerCase()}',
        f.bytes!,
      );
      await store.api.patch('/servers/${widget.serverId}', {field: id});
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final s = store.servers[widget.serverId]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconAvatar(
              url: store.api.fileUrl('icons', s['icon'] as Map?, width: 128),
              name: s['name'] as String? ?? '?',
              size: 72,
            ),
            const SizedBox(width: 16),
            FilledButton.tonal(
              onPressed: () => _upload('icons', 'icon'),
              child: const Text('Change icon'),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: () => _upload('banners', 'banner'),
              child: const Text('Change banner'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          decoration: InputDecoration(labelText: tr('Server Name')),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _desc,
          minLines: 3,
          maxLines: 8,
          decoration: InputDecoration(labelText: tr('Server Description')),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => _guard(context, () async {
            await store.api.patch('/servers/${widget.serverId}', {
              'name': _name.text.trim(),
              'description': _desc.text,
            });
            if (mounted) showSnack(context, 'Saved');
          }),
          child: Text(tr('Save')),
        ),
      ],
    );
  }
}

class _Emojis extends StatefulWidget {
  const _Emojis({required this.serverId});
  final String serverId;
  @override
  State<_Emojis> createState() => _EmojisState();
}

class _EmojisState extends State<_Emojis> {
  List<Map<String, dynamic>>? _list;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await context.read<ClientStore>().api.get(
      '/servers/${widget.serverId}/emojis',
    ) as List;
    if (mounted)
      setState(
        () => _list = r.map((e) => (e as Map).cast<String, dynamic>()).toList(),
      );
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
          label: const Text('Upload emoji'),
          onPressed: () async {
            final res = await FilePicker.platform.pickFiles(
              type: FileType.image,
              withData: true,
            );
            final f = res?.files.firstOrNull;
            if (f?.bytes == null || !context.mounted) return;
            final name = await promptText(
              context,
              'Emoji name',
              label: 'name (a-z, 0-9, _)',
              initial: f!.name
                  .split('.')
                  .first
                  .toLowerCase()
                  .replaceAll(RegExp(r'[^a-z0-9_]'), '_'),
            );
            if (name == null || name.isEmpty || !context.mounted) return;
            await _guard(context, () async {
              final id = await store.api.uploadFile(
                'emojis',
                f.name,
                'image/${(f.extension ?? 'png').toLowerCase()}',
                f.bytes!,
              );
              await store.api.put('/custom/emoji/$id', {
                'name': name,
                'parent': {'type': 'Server', 'id': widget.serverId},
              });
              _load();
            });
          },
        ),
        const SizedBox(height: 16),
        CategoryGroup(
          children: [
            for (final e in list)
              CategoryButton(
                icon: NetImage(
                  '${store.api.config?.autumnUrl}/emojis/${e['_id']}',
                  width: 28,
                  height: 28,
                ),
                title: Text(':${e['name']}:'),
                action: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _guard(context, () async {
                    await store.api.delete('/custom/emoji/${e['_id']}');
                    _load();
                  }),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Members extends StatelessWidget {
  const _Members({required this.serverId});
  final String serverId;
  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final ids = store.members[serverId]?.keys.toList() ?? [];
    if (ids.isEmpty) {
      store.loadMembers(serverId);
      return const Center(child: CircularProgressIndicator());
    }
    return CategoryGroup(
      children: [
        for (final id in ids)
          CategoryButton(
            icon: UserAvatar(userId: id, size: 28),
            title: Text(store.displayName(id, server: serverId)),
            action: id == store.userId
                ? null
                : PopupMenuButton<String>(
                    onSelected: (v) => _guard(context, () async {
                      if (v == 'kick') {
                        await store.api.delete(
                          '/servers/$serverId/members/$id',
                        );
                        store.members[serverId]?.remove(id);
                      } else {
                        await store.api.put('/servers/$serverId/bans/$id', {});
                        store.members[serverId]?.remove(id);
                      }
                      store.refresh();
                    }),
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'kick', child: Text(tr('Kick'))),
                      PopupMenuItem(value: 'ban', child: Text(tr('Ban'))),
                    ],
                  ),
          ),
      ],
    );
  }
}

class _Roles extends StatelessWidget {
  const _Roles({required this.serverId});
  final String serverId;
  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final roles = ((store.servers[serverId]?['roles'] as Map?) ?? {})
        .cast<String, dynamic>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton.icon(
          icon: const Icon(Icons.add),
          label: Text(tr('Create Role')),
          onPressed: () async {
            final name = await promptText(
              context,
              tr('Create Role'),
              label: tr('Role Name'),
              action: tr('Create'),
            );
            if (name == null || name.isEmpty || !context.mounted) return;
            await _guard(context, () async {
              final r = await store.api.post('/servers/$serverId/roles', {
                'name': name,
              }) as Map;
              ((store.servers[serverId]!['roles'] ??= <String, dynamic>{})
                  as Map)[r['id']] = (r['role'] as Map)
                  .cast<String, dynamic>();
              store.refresh();
            });
          },
        ),
        const SizedBox(height: 16),
        CategoryGroup(
          children: [
            for (final e in roles.entries)
              CategoryButton(
                icon: Icon(
                  Icons.circle,
                  color: _colour((e.value as Map)['colour'] as String?),
                ),
                title: Text((e.value as Map)['name'] as String? ?? ''),
                action: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () async {
                        final name = await promptText(
                          context,
                          'Rename role',
                          initial: (e.value as Map)['name'] as String?,
                        );
                        if (name == null || name.isEmpty || !context.mounted)
                          return;
                        await _guard(context, () async {
                          await store.api.patch(
                            '/servers/$serverId/roles/${e.key}',
                            {'name': name},
                          );
                          (e.value as Map)['name'] = name;
                          store.refresh();
                        });
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _guard(context, () async {
                        await store.api.delete(
                          '/servers/$serverId/roles/${e.key}',
                        );
                        roles.remove(e.key);
                        store.refresh();
                      }),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  Color _colour(String? c) {
    if (c == null) return Colors.grey;
    final m = RegExp(r'#([0-9a-fA-F]{6})').firstMatch(c);
    return m == null ? Colors.grey : parseHex('#${m.group(1)}');
  }
}

class _Invites extends StatefulWidget {
  const _Invites({required this.serverId});
  final String serverId;
  @override
  State<_Invites> createState() => _InvitesState();
}

class _InvitesState extends State<_Invites> {
  List<Map<String, dynamic>>? _list;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await context.read<ClientStore>().api.get(
      '/servers/${widget.serverId}/invites',
    ) as List;
    if (mounted)
      setState(
        () => _list = r.map((e) => (e as Map).cast<String, dynamic>()).toList(),
      );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<ClientStore>();
    final list = _list;
    if (list == null) return const Center(child: CircularProgressIndicator());
    final firstText = store
        .channelsOfServer(widget.serverId)
        .where((c) => c['channel_type'] == 'TextChannel')
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (firstText != null)
          FilledButton.icon(
            icon: const Icon(Icons.add_link),
            label: Text(tr('Create invite')),
            onPressed: () => _guard(context, () async {
              await store.api.post('/channels/${firstText['_id']}/invites');
              _load();
            }),
          ),
        const SizedBox(height: 16),
        CategoryGroup(
          children: [
            for (final i in list)
              CategoryButton(
                icon: const Icon(Icons.link),
                title: Text(i['_id'] as String),
                description: Text(
                  'Created by ${store.displayName(i['creator'] as String?)}',
                ),
                action: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.copy),
                      onPressed: () => copyText(
                        context,
                        '${store.api.config?.app ?? ''}/invite/${i['_id']}',
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _guard(context, () async {
                        await store.api.delete('/invites/${i['_id']}');
                        _load();
                      }),
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

class _Bans extends StatefulWidget {
  const _Bans({required this.serverId});
  final String serverId;
  @override
  State<_Bans> createState() => _BansState();
}

class _BansState extends State<_Bans> {
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = ((await context.read<ClientStore>().api.get(
      '/servers/${widget.serverId}/bans',
    )) as Map).cast<String, dynamic>();
    if (mounted) setState(() => _data = r);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<ClientStore>();
    final d = _data;
    if (d == null) return const Center(child: CircularProgressIndicator());
    final users = {
      for (final u in (d['users'] as List)) (u as Map)['_id'] as String: u,
    };
    final bans = (d['bans'] as List).cast<Map>();
    if (bans.isEmpty) return const Text('No bans.');
    return CategoryGroup(
      children: [
        for (final b in bans)
          CategoryButton(
            icon: const Icon(Icons.gavel),
            title: Text(
              '${users[(b['_id'] as Map)['user']]?['username'] ?? (b['_id'] as Map)['user']}',
            ),
            description: Text((b['reason'] as String?) ?? 'No reason'),
            action: TextButton(
              onPressed: () => _guard(context, () async {
                await store.api.delete(
                  '/servers/${widget.serverId}/bans/${(b['_id'] as Map)['user']}',
                );
                _load();
              }),
              child: const Text('Unban'),
            ),
          ),
      ],
    );
  }
}
