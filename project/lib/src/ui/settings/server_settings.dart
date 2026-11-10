import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../net_image.dart';
import 'package:provider/provider.dart';

import '../../api/client_store.dart';
import '../../api/permissions.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../widgets.dart';
import '../modals/member_modals.dart';
import '../profile/profile.dart' show showUserRoles;
import '../../core/i18n.dart';
import 'permission_editor.dart';
import 'role_editor.dart';

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
    if (server == null) {
      return const Scaffold(body: Center(child: Text('Server not found')));
    }
    final phone =
        screenClassOf(MediaQuery.sizeOf(context)) == ScreenClass.phone;
    final entries = [
      for (final section in _entries)
        (section.$1, [
          for (final entry in section.$2)
            if (switch (entry.$1) {
              'roles' => store.canInServer(widget.serverId, Perm.manageRole) || store.canInServer(widget.serverId, Perm.managePermissions),
              'emojis' => store.canInServer(widget.serverId, Perm.manageCustomisation),
              'invites' => store.canInServer(widget.serverId, Perm.manageServer),
              'bans' => store.canInServer(widget.serverId, Perm.banMembers),
              _ => true,
            }) entry,
        ]),
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
            server['name'] as String? ?? '',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
        ),
        for (final cat in entries) ...[
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
              selected: _page.split('/').first == e.$1,
              selectedTileColor: cs.secondaryContainer,
              leading: Icon(e.$3),
              title: Text(tr(e.$2)),
              onTap: () => setState(() => _page = e.$1),
            ),
        ],
        const Divider(),
        if (server['owner'] == store.userId) ListTile(
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
      clipBehavior: Clip.antiAlias,
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
            child: _page == 'roles/default'
                ? PermissionSettings(
                    key: const ValueKey('server-default'),
                    initial: server['default_permissions'], overrides: false,
                    onSave: (value) async {
                      await store.api.put('/servers/${widget.serverId}/permissions/default', {'permissions': value.allow.toInt()});
                      server['default_permissions'] = value.allow.toInt();
                      store.refresh();
                    },
                  )
                : _page.startsWith('roles/')
                ? RoleEditor(key: ValueKey(_page), serverId: widget.serverId, roleId: _page.substring(6), onBack: () => setState(() => _page = 'roles'))
                : switch (_page) {
              'overview' => _Overview(serverId: widget.serverId),
              'emojis' => _Emojis(serverId: widget.serverId),
              'members' => _Members(serverId: widget.serverId),
              'roles' => _Roles(serverId: widget.serverId, onEdit: (id) => setState(() => _page = 'roles/$id')),
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
                entries
                    .expand((c) => c.$2)
                    .firstWhere((e) => e.$1 == _page.split('/').first)
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
                    for (final c in entries)
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
  late final Map<String, dynamic> _system = Map<String, dynamic>.from(
    context.read<ClientStore>().servers[widget.serverId]?['system_messages'] as Map? ?? {},
  );
  bool _busy = false;
  PlatformFile? _iconFile, _bannerFile;
  bool _removeIcon = false, _removeBanner = false;

  void _reset() => setState(() {
    final server = context.read<ClientStore>().servers[widget.serverId]!;
    _name.text = server['name'] as String? ?? '';
    _desc.text = server['description'] as String? ?? '';
    _system..clear()..addAll((server['system_messages'] as Map?)?.cast<String, dynamic>() ?? {});
    _iconFile = _bannerFile = null;
    _removeIcon = _removeBanner = false;
  });

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _removeImage(String field) => setState(() {
    if (field == 'icon') { _iconFile = null; _removeIcon = true; }
    else { _bannerFile = null; _removeBanner = true; }
  });

  Future<void> _upload(String tag, String field) async {
    final res = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final f = res?.files.firstOrNull;
    if (f?.bytes == null) return;
    if (!mounted) return;
    setState(() {
      if (field == 'icon') { _iconFile = f; _removeIcon = false; }
      else { _bannerFile = f; _removeBanner = false; }
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final s = store.servers[widget.serverId]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (_iconFile?.bytes != null)
              ClipOval(child: Image.memory(_iconFile!.bytes!, width: 72, height: 72, fit: BoxFit.cover))
            else IconAvatar(
              url: _removeIcon ? null : store.api.fileUrl('icons', s['icon'] as Map?, width: 128),
              name: s['name'] as String? ?? '?',
              size: 72,
            ),
            const SizedBox(width: 16),
            FilledButton.tonal(
              onPressed: () => _upload('icons', 'icon'),
              child: const Text('Change icon'),
            ),
            if (!_removeIcon && (s['icon'] != null || _iconFile != null)) IconButton(tooltip: tr('Remove'), icon: const Icon(Icons.delete_outline), onPressed: () => _removeImage('icon')),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: () => _upload('banners', 'banner'),
              child: const Text('Change banner'),
            ),
            if (!_removeBanner && (s['banner'] != null || _bannerFile != null)) IconButton(tooltip: tr('Remove'), icon: const Icon(Icons.delete_outline), onPressed: () => _removeImage('banner')),
          ],
        ),
        if (!_removeBanner && (_bannerFile?.bytes != null || s['banner'] != null))
          Padding(padding: const EdgeInsets.only(top: 12), child: ClipRRect(
            borderRadius: br(Radius_.sm),
            child: AspectRatio(aspectRatio: 2.32, child: _bannerFile?.bytes != null
                ? Image.memory(_bannerFile!.bytes!, fit: BoxFit.cover)
                : NetImage(store.api.fileUrl('banners', s['banner'] as Map?, width: 800) ?? '', fit: BoxFit.cover)),
          )),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          maxLength: 32,
          decoration: InputDecoration(labelText: tr('Server Name')),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _desc,
          minLines: 3,
          maxLines: 8,
          maxLength: 1024,
          decoration: InputDecoration(labelText: tr('Server Description')),
        ),
        const SizedBox(height: 16),
        SectionTitle(tr('System message channels')),
        for (final entry in const {'user_joined': 'User Joined', 'user_left': 'User Left', 'user_kicked': 'User Kicked', 'user_banned': 'User Banned'}.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DropdownButtonFormField<String>(
              initialValue: store.channels.containsKey(_system[entry.key]) ? _system[entry.key] as String : 'none',
              isExpanded: true, decoration: InputDecoration(labelText: tr(entry.value)),
              items: [DropdownMenuItem(value: 'none', child: Text(tr('Disabled'))),
                for (final channel in store.channelsOfServer(widget.serverId))
                  DropdownMenuItem(value: channel['_id'] as String, child: Text(store.channelName(channel))),
              ],
              onChanged: _busy ? null : (next) => setState(() {
                if (next == null || next == 'none') { _system.remove(entry.key); } else { _system[entry.key] = next; }
              }),
            ),
          ),
        FilledButton(
          onPressed: _busy ? null : () => _guard(context, () async {
            if (_name.text.trim().isEmpty) return;
            setState(() => _busy = true);
            try {
            final remove = <String>[
              if (_desc.text.trim().isEmpty) 'Description',
              if (_removeIcon) 'Icon', if (_removeBanner) 'Banner',
            ];
            final body = <String, dynamic>{
              'name': _name.text.trim(),
              if (_desc.text.trim().isNotEmpty) 'description': _desc.text.trim(),
              if (remove.isNotEmpty) 'remove': remove,
              'system_messages': Map<String, dynamic>.from(_system),
            };
            for (final entry in {'icon': _iconFile, 'banner': _bannerFile}.entries) {
              final file = entry.value;
              if (file?.bytes != null) {
                body[entry.key] = await store.api.uploadFile(entry.key == 'icon' ? 'icons' : 'banners', file!.name, mimeFromNameSimple(file.name), file.bytes!);
              }
            }
            final response = await store.api.patch('/servers/${widget.serverId}', body);
            s.addAll({'name': _name.text.trim(), 'description': _desc.text.trim(), 'system_messages': Map<String, dynamic>.from(_system)});
            if (_removeIcon) s.remove('icon');
            if (_removeBanner) s.remove('banner');
            if (response is Map) s.addAll(response.cast<String, dynamic>());
            store.refresh();
            if (mounted) _reset();
            if (mounted) showSnack(context, 'Saved');
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          }),
          child: Text(tr('Save')),
        ),
        TextButton(onPressed: _busy ? null : _reset, child: Text(tr('Reset'))),
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
    if (mounted) {
      setState(
        () => _list = r.map((e) => (e as Map).cast<String, dynamic>()).toList(),
      );
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
          label: const Text('Upload emoji'),
          onPressed: () async {
            final res = await FilePicker.pickFiles(
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
                onTap: () async {
                  final name = await promptText(context, tr('Rename emoji'), label: tr('Emoji Name'), initial: e['name'] as String?);
                  if (name == null || !RegExp(r'^[a-z0-9_]{1,32}$').hasMatch(name) || !context.mounted) return;
                  await _guard(context, () async {
                    await store.api.patch('/custom/emoji/${e['_id']}', {'name': name});
                    await _load();
                  });
                },
                icon: NetImage(
                  '${store.api.config?.autumnUrl}/emojis/${e['_id']}',
                  width: 28,
                  height: 28,
                ),
                title: Text(':${e['name']}:'),
                action: IconButton(
                  tooltip: tr('Delete Emoji'),
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
            onTap: () => showUserRoles(context, serverId, id),
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
  const _Roles({required this.serverId, required this.onEdit});
  final String serverId;
  final ValueChanged<String> onEdit;
  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final roles = ((store.servers[serverId]?['roles'] as Map?) ?? {})
        .cast<String, dynamic>();
    final ordered = roles.keys.toList()
      ..sort((first, second) => ((roles[first]['rank'] as num?) ?? 0).compareTo((roles[second]['rank'] as num?) ?? 0));
    final canEdit = store.canInServer(serverId, Perm.manageRole);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (canEdit) FilledButton.icon(
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
              onEdit(r['id'] as String);
            });
          },
        ),
        const SizedBox(height: 16),
        ReorderableListView(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorder: (oldIndex, newIndex) async {
            if (!canEdit) return;
            final next = List<String>.from(ordered);
            if (newIndex > oldIndex) newIndex--;
            next.insert(newIndex, next.removeAt(oldIndex));
            await _guard(context, () async {
              await store.api.patch('/servers/$serverId/roles', {'roles': next});
              for (var index = 0; index < next.length; index++) {
                (roles[next[index]] as Map)['rank'] = index;
              }
              store.refresh();
            });
          },
          children: [
            for (final id in ordered)
              Material(key: ValueKey(id), color: context.cs.surfaceContainerHigh, child:
              CategoryButton(
                key: ValueKey('role-$id'),
                icon: Icon(
                  Icons.circle,
                  color: _colour((roles[id] as Map)['colour'] as String?),
                ),
                title: Text((roles[id] as Map)['name'] as String? ?? ''),
                onTap: () => onEdit(id),
                action: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => onEdit(id),
                    ),
                    if (canEdit) ReorderableDragStartListener(index: ordered.indexOf(id), child: const Tooltip(message: 'Reorder role', child: Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_handle)))),
                    if (canEdit) IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _guard(context, () async {
                        await store.api.delete(
                          '/servers/$serverId/roles/$id',
                        );
                        roles.remove(id);
                        store.refresh();
                      }),
                    ),
                  ],
                ),
              )),
          ],
        ),
        CategoryButton(
          icon: const Icon(Icons.public), title: Text(tr('Everyone')),
          description: Text(tr('Permissions available without any role')),
          action: const Icon(Icons.chevron_right), onTap: () => onEdit('default'),
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
    if (mounted) {
      setState(
        () => _list = r.map((e) => (e as Map).cast<String, dynamic>()).toList(),
      );
    }
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
  String _nameFilter = '', _reasonFilter = '';

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
    final bans = (d['bans'] as List).cast<Map>().where((ban) {
      final name = '${users[(ban['_id'] as Map)['user']]?['username'] ?? ''}'.toLowerCase();
      return name.contains(_nameFilter.toLowerCase()) && '${ban['reason'] ?? ''}'.toLowerCase().contains(_reasonFilter.toLowerCase());
    }).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
      TextField(decoration: InputDecoration(labelText: tr('User')), onChanged: (value) => setState(() => _nameFilter = value)),
      TextField(decoration: InputDecoration(labelText: tr('Reason')), onChanged: (value) => setState(() => _reasonFilter = value)),
      if (bans.isEmpty) Text(tr('No bans.')),
      CategoryGroup(
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
    )]);
  }
}
