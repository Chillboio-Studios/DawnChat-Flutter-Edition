import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../net_image.dart';

import 'package:provider/provider.dart';

import '../../api/client_store.dart';
import '../../api/permissions.dart';
import '../../state/channel_ordering.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../image_cropper.dart';
import '../widgets.dart';
import '../modals/channel_modals.dart';
import '../modals/member_modals.dart';
import '../modals/server_modals.dart';
import '../profile/profile.dart' show showUserRoles;
import '../../core/i18n.dart';
import 'permission_editor.dart';
import 'role_editor.dart';
import 'settings_page.dart' show SettingsNavRow;

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

  // Mirrors the web client's `ServerSettings.list()`: the first category is
  // titled with the server name, "Members" is intentionally hidden, and whole
  // categories are hidden when the user lacks every permission they gate on.
  List<(String, List<(String, String, IconData)>)> _entriesFor(
    Map<String, dynamic> server,
  ) {
    final store = context.read<ClientStore>();
    final sid = widget.serverId;
    bool has(BigInt p) => store.canInServer(sid, p);
    return [
      (
        server['name'] as String? ?? '',
        [
          ('overview', 'Overview', Icons.info_outline),
          if (server['owner'] == store.userId)
            ('discover', 'Discover', Icons.public),
          if (has(Perm.manageChannel) || has(Perm.manageServer))
            ('channels', 'Channels', Icons.account_tree_outlined),
        ],
      ),
      if (has(Perm.manageCustomisation))
        (
          'Customisation',
          [('emojis', 'Emojis', Icons.emoji_emotions_outlined)],
        ),
      if (has(Perm.manageServer) || has(Perm.banMembers))
        (
          tr('User Management'),
          [
            if (has(Perm.manageRole) || has(Perm.managePermissions))
              ('roles', 'Roles', Icons.flag_outlined),
            if (has(Perm.manageServer)) ('invites', 'Invites', Icons.link),
            if (has(Perm.banMembers)) ('bans', 'Bans', Icons.gavel),
          ],
        ),
    ];
  }

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
      for (final section in _entriesFor(server))
        if (section.$2.isNotEmpty) section,
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
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: SettingsNavRow(
                icon: e.$3,
                title: tr(e.$2),
                selected: _page.split('/').first == e.$1,
                onTap: () => setState(() => _page = e.$1),
              ),
            ),
        ],
        const Divider(),
        if (server['owner'] == store.userId)
          ListTile(
            leading: Icon(Icons.delete_outline, color: cs.error),
            title: Text(tr('Delete Server'), style: TextStyle(color: cs.error)),
            onTap: () async {
              if (await confirm(
                context,
                'Delete ${server['name']}?',
                "Once it's deleted, there's no going back.",
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
                    initial: server['default_permissions'],
                    overrides: false,
                    onSave: (value) async {
                      await store.api.put(
                        '/servers/${widget.serverId}/permissions/default',
                        {'permissions': value.allow.toInt()},
                      );
                      server['default_permissions'] = value.allow.toInt();
                      store.refresh();
                    },
                  )
                : _page.startsWith('roles/')
                ? RoleEditor(
                    key: ValueKey(_page),
                    serverId: widget.serverId,
                    roleId: _page.substring(6),
                    onBack: () => setState(() => _page = 'roles'),
                  )
                : switch (_page) {
                    'overview' => _Overview(serverId: widget.serverId),
                    'discover' => _Discoverable(serverId: widget.serverId),
                    'channels' => _ChannelOrder(serverId: widget.serverId),
                    'emojis' => _Emojis(serverId: widget.serverId),
                    'members' => _Members(serverId: widget.serverId),
                    'roles' => _Roles(
                      serverId: widget.serverId,
                      onEdit: (id) => setState(() => _page = 'roles/$id'),
                    ),
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
    context.read<ClientStore>().servers[widget.serverId]?['system_messages']
            as Map? ??
        {},
  );
  bool _busy = false;
  PickedImage? _iconFile, _bannerFile;
  bool _removeIcon = false, _removeBanner = false;

  void _reset() => setState(() {
    final server = context.read<ClientStore>().servers[widget.serverId]!;
    _name.text = server['name'] as String? ?? '';
    _desc.text = server['description'] as String? ?? '';
    _system
      ..clear()
      ..addAll(
        (server['system_messages'] as Map?)?.cast<String, dynamic>() ?? {},
      );
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
    if (field == 'icon') {
      _iconFile = null;
      _removeIcon = true;
    } else {
      _bannerFile = null;
      _removeBanner = true;
    }
  });

  Future<void> _upload(String field) async {
    final isIcon = field == 'icon';
    final p = await pickImageForUpload(
      context,
      shape: CropShape.rect,
      aspectRatio: isIcon ? 1 : 2.32,
      name: isIcon ? 'icon' : 'banner',
    );
    if (p == null || !mounted) return;
    setState(() {
      if (isIcon) {
        _iconFile = p;
        _removeIcon = false;
      } else {
        _bannerFile = p;
        _removeBanner = false;
      }
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
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (_iconFile != null)
              ClipRRect(
                borderRadius: br(10),
                child: Image.memory(
                  _iconFile!.bytes,
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                ),
              )
            else
              IconAvatar(
                url: _removeIcon
                    ? null
                    : store.api.fileUrl('icons', s['icon'] as Map?, width: 128),
                name: s['name'] as String? ?? '?',
                size: 72,
              ),
            const SizedBox(width: 16),
            FilledButton.tonal(
              onPressed: () => _upload('icon'),
              child: const Text('Change icon'),
            ),
            if (!_removeIcon && (s['icon'] != null || _iconFile != null))
              IconButton(
                tooltip: tr('Remove'),
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _removeImage('icon'),
              ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: () => _upload('banner'),
              child: const Text('Change banner'),
            ),
            if (!_removeBanner && (s['banner'] != null || _bannerFile != null))
              IconButton(
                tooltip: tr('Remove'),
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _removeImage('banner'),
              ),
          ],
        ),
        if (!_removeBanner && (_bannerFile != null || s['banner'] != null))
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: ClipRRect(
              borderRadius: br(Radius_.sm),
              child: AspectRatio(
                aspectRatio: 2.32,
                child: _bannerFile != null
                    ? Image.memory(_bannerFile!.bytes, fit: BoxFit.cover)
                    : NetImage(
                        store.api.fileUrl(
                              'banners',
                              s['banner'] as Map?,
                              width: 800,
                            ) ??
                            '',
                        fit: BoxFit.cover,
                      ),
              ),
            ),
          ),
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
        for (final entry in const {
          'user_joined': 'User Joined',
          'user_left': 'User Left',
          'user_kicked': 'User Kicked',
          'user_banned': 'User Banned',
        }.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DropdownButtonFormField<String>(
              initialValue: store.channels.containsKey(_system[entry.key])
                  ? _system[entry.key] as String
                  : 'none',
              isExpanded: true,
              decoration: InputDecoration(labelText: tr(entry.value)),
              items: [
                DropdownMenuItem(value: 'none', child: Text(tr('Disabled'))),
                for (final channel in store.channelsOfServer(widget.serverId))
                  DropdownMenuItem(
                    value: channel['_id'] as String,
                    child: Text(store.channelName(channel)),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (next) => setState(() {
                      if (next == null || next == 'none') {
                        _system.remove(entry.key);
                      } else {
                        _system[entry.key] = next;
                      }
                    }),
            ),
          ),
        FilledButton(
          onPressed: _busy
              ? null
              : () => _guard(context, () async {
                  if (_name.text.trim().isEmpty) return;
                  setState(() => _busy = true);
                  try {
                    final remove = <String>[
                      if (_desc.text.trim().isEmpty) 'Description',
                      if (_removeIcon) 'Icon',
                      if (_removeBanner) 'Banner',
                    ];
                    final body = <String, dynamic>{
                      'name': _name.text.trim(),
                      if (_desc.text.trim().isNotEmpty)
                        'description': _desc.text.trim(),
                      if (remove.isNotEmpty) 'remove': remove,
                      'system_messages': Map<String, dynamic>.from(_system),
                    };
                    for (final entry in {
                      'icon': _iconFile,
                      'banner': _bannerFile,
                    }.entries) {
                      final file = entry.value;
                      if (file != null) {
                        body[entry.key] = await store.api.uploadFile(
                          entry.key == 'icon' ? 'icons' : 'banners',
                          file.name,
                          mimeFromNameSimple(file.name),
                          file.bytes,
                        );
                      }
                    }
                    final response = await store.api.patch(
                      '/servers/${widget.serverId}',
                      body,
                    );
                    s.addAll({
                      'name': _name.text.trim(),
                      'description': _desc.text.trim(),
                      'system_messages': Map<String, dynamic>.from(_system),
                    });
                    if (_removeIcon) s.remove('icon');
                    if (_removeBanner) s.remove('banner');
                    if (response is Map)
                      s.addAll(response.cast<String, dynamic>());
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
        () => _list = r.map((e) => (e as Map).cast<String, dynamic>()).toList()
          // Web sorts by id descending (newest first).
          ..sort((a, b) => (b['_id'] as String).compareTo(a['_id'] as String)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<ClientStore>();
    final list = _list;
    if (list == null) return const Center(child: CircularProgressIndicator());
    final cfg = store.api.config;
    final limit =
        (((cfg?.limits['global'] ?? cfg?.limits['new_user'])
                    as Map?)?['server_emoji']
                as num?)
            ?.toInt() ??
        100;
    final remaining = (limit - list.length).clamp(0, limit);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('$remaining emoji slots remaining'),
          style: TextStyle(fontSize: 12, color: context.cs.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          icon: const Icon(Icons.add),
          label: Text(tr('Upload emoji')),
          onPressed: () async {
            final f = await FilePicker.pickFile(type: FileType.image);
            final fBytes = f == null ? null : await f.readAsBytes();
            if (fBytes == null || !context.mounted) return;
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
                fBytes,
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
                  final name = await promptText(
                    context,
                    tr('Rename emoji'),
                    label: tr('Emoji Name'),
                    initial: e['name'] as String?,
                  );
                  if (name == null ||
                      !RegExp(r'^[a-z0-9_]{1,32}$').hasMatch(name) ||
                      !context.mounted)
                    return;
                  await _guard(context, () async {
                    await store.api.patch('/custom/emoji/${e['_id']}', {
                      'name': name,
                    });
                    await _load();
                  });
                },
                icon: NetImage(
                  '${store.api.config?.autumnUrl}/emojis/${e['_id']}',
                  width: 28,
                  height: 28,
                ),
                title: Text(':${e['name']}:'),
                description: e['creator_id'] != null
                    ? Text(
                        store.displayName(e['creator_id'] as String?),
                        style: const TextStyle(fontSize: 12),
                      )
                    : null,
                action: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: tr('Preview'),
                      icon: const Icon(Icons.zoom_in, size: 20),
                      onPressed: () => showEmojiPreview(
                        context,
                        name: '${e['name']}',
                        url:
                            '${store.api.config?.autumnUrl}/emojis/${e['_id']}',
                      ),
                    ),
                    IconButton(
                      tooltip: tr('Delete Emoji'),
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _guard(context, () async {
                        await store.api.delete('/custom/emoji/${e['_id']}');
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
    // Highest role first; the owner outranks everyone.
    final server = store.servers[serverId];
    final roles = (server?['roles'] as Map?) ?? const {};
    int topRank(String id) {
      if (id == server?['owner']) return -1;
      final memberRoles =
          ((store.members[serverId]?[id]?['roles'] as List?) ?? const [])
              .cast<String>();
      var best = 1 << 30;
      for (final rid in memberRoles) {
        final r = ((roles[rid] as Map?)?['rank'] as num?)?.toInt();
        if (r != null && r < best) best = r;
      }
      return best;
    }

    ids.sort((a, b) => topRank(a).compareTo(topRank(b)));
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

  /// Roles are hierarchical: a lower [rank] means a more powerful role and is
  /// shown higher in the list. Ties keep their previous relative order.
  static List<String> _hierarchy(Map<String, dynamic> roles) {
    final ids = roles.keys.toList();
    final indexed =
        [
          for (var i = 0; i < ids.length; i++)
            (
              id: ids[i],
              rank: ((roles[ids[i]] as Map)['rank'] as num?) ?? 0,
              index: i,
            ),
        ]..sort((a, b) {
          final r = a.rank.compareTo(b.rank);
          return r != 0 ? r : a.index.compareTo(b.index);
        });
    return [for (final e in indexed) e.id];
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final roles = ((store.servers[serverId]?['roles'] as Map?) ?? {})
        .cast<String, dynamic>();
    final ordered = _hierarchy(roles);
    final canEdit = store.canInServer(serverId, Perm.manageRole);
    final phone =
        screenClassOf(MediaQuery.sizeOf(context)) == ScreenClass.phone;

    Future<void> applyOrder(List<String> next) => _guard(context, () async {
      await store.api.patch('/servers/$serverId/roles/ranks', {'ranks': next});
      for (var index = 0; index < next.length; index++) {
        (roles[next[index]] as Map)['rank'] = index;
      }
      store.refresh();
    });

    void move(String id, int delta) {
      final next = List<String>.from(ordered);
      final from = next.indexOf(id);
      final to = (from + delta).clamp(0, next.length - 1);
      if (to == from) return;
      next.insert(to, next.removeAt(from));
      applyOrder(next);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (canEdit)
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
                onEdit(r['id'] as String);
              });
            },
          ),
        const SizedBox(height: 8),
        Text(
          tr(
            'Roles are ordered by hierarchy — the top role is the most powerful.',
          ),
          style: TextStyle(fontSize: 12, color: context.cs.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (oldIndex, newIndex) {
            if (!canEdit) return;
            final next = List<String>.from(ordered);
            next.insert(newIndex, next.removeAt(oldIndex));
            applyOrder(next);
          },
          children: [
            for (var i = 0; i < ordered.length; i++)
              Material(
                key: ValueKey(ordered[i]),
                color: context.cs.surfaceContainerHigh,
                child: CategoryButton(
                  key: ValueKey('role-${ordered[i]}'),
                  icon: Icon(
                    Icons.circle,
                    color: _colour(
                      (roles[ordered[i]] as Map)['colour'] as String?,
                    ),
                  ),
                  title: Text(
                    (roles[ordered[i]] as Map)['name'] as String? ?? '',
                  ),
                  description: Text('${i + 1}'),
                  onTap: () => onEdit(ordered[i]),
                  action: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (canEdit)
                        IconButton(
                          tooltip: tr('Move up'),
                          icon: const Icon(Icons.arrow_upward, size: 18),
                          onPressed: i > 0 ? () => move(ordered[i], -1) : null,
                        ),
                      if (canEdit)
                        IconButton(
                          tooltip: tr('Move down'),
                          icon: const Icon(Icons.arrow_downward, size: 18),
                          onPressed: i < ordered.length - 1
                              ? () => move(ordered[i], 1)
                              : null,
                        ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => onEdit(ordered[i]),
                      ),
                      if (canEdit && !phone)
                        ReorderableDragStartListener(
                          index: i,
                          child: const Tooltip(
                            message: 'Reorder role',
                            child: Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.drag_handle),
                            ),
                          ),
                        ),
                      if (canEdit)
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _guard(context, () async {
                            await store.api.delete(
                              '/servers/$serverId/roles/${ordered[i]}',
                            );
                            roles.remove(ordered[i]);
                            store.refresh();
                          }),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        CategoryButton(
          icon: const Icon(Icons.public),
          title: Text(tr('Everyone')),
          description: Text(tr('Permissions available without any role')),
          action: const Icon(Icons.chevron_right),
          onTap: () => onEdit('default'),
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
      final name = '${users[(ban['_id'] as Map)['user']]?['username'] ?? ''}'
          .toLowerCase();
      return name.contains(_nameFilter.toLowerCase()) &&
          '${ban['reason'] ?? ''}'.toLowerCase().contains(
            _reasonFilter.toLowerCase(),
          );
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        TextField(
          decoration: InputDecoration(labelText: tr('User')),
          onChanged: (value) => setState(() => _nameFilter = value),
        ),
        TextField(
          decoration: InputDecoration(labelText: tr('Reason')),
          onChanged: (value) => setState(() => _reasonFilter = value),
        ),
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
        ),
      ],
    );
  }
}

/// Channel & category ordering editor (the web client's drag handles, also
/// usable on touch devices via the arrow buttons).
class _ChannelOrder extends StatefulWidget {
  const _ChannelOrder({required this.serverId});
  final String serverId;
  @override
  State<_ChannelOrder> createState() => _ChannelOrderState();
}

class _ChannelOrderState extends State<_ChannelOrder> {
  List<OrderedCategory>? _cats;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final store = context.read<ClientStore>();
    final server = store.servers[widget.serverId];
    final all = store.channelsOfServer(widget.serverId);
    _cats = orderedCategories(server?['categories'] as List?, [
      for (final c in all) c['_id'] as String,
    ]);
  }

  Future<void> _save() => _guard(context, () async {
    setState(() => _busy = true);
    try {
      await saveServerCategories(
        context.read<ClientStore>(),
        widget.serverId,
        _cats ?? const [],
      );
      if (mounted) showSnack(context, 'Saved');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  });

  void _moveChannel(int cat, int index, int delta) {
    final ids = _cats![cat].channelIds;
    final to = (index + delta).clamp(0, ids.length - 1);
    if (to == index) return;
    setState(() => ids.insert(to, ids.removeAt(index)));
  }

  void _moveChannelTo(int from, String channelId, int to) {
    if (from == to) return;
    setState(() {
      _cats![from].channelIds.remove(channelId);
      _cats![to].channelIds.add(channelId);
    });
  }

  void _moveCategory(int index, int delta) {
    // The 'default' (uncategorised) bucket always stays on top.
    final cats = _cats!;
    final firstMovable = cats.indexWhere((c) => c.id != 'default');
    if (firstMovable < 0) return;
    final from = index < firstMovable ? firstMovable : index;
    var to = (from + delta).clamp(firstMovable, cats.length - 1);
    if (to == from) return;
    setState(() => cats.insert(to, cats.removeAt(from)));
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final cs = context.cs;
    final cats = _cats;
    if (cats == null) return const Center(child: CircularProgressIndicator());
    final canEdit =
        store.canInServer(widget.serverId, Perm.manageChannel) && !_busy;

    Widget upDown({
      required bool canUp,
      required bool canDown,
      required void Function(int) move,
    }) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: tr('Move up'),
            icon: const Icon(Icons.arrow_upward, size: 18),
            onPressed: canEdit && canUp ? () => move(-1) : null,
          ),
          IconButton(
            tooltip: tr('Move down'),
            icon: const Icon(Icons.arrow_downward, size: 18),
            onPressed: canEdit && canDown ? () => move(1) : null,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('Drag or use the arrows to reorder categories and channels.'),
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        if (canEdit)
          Wrap(
            spacing: 8,
            children: [
              FilledButton.tonalIcon(
                icon: const Icon(Icons.add),
                label: Text(tr('Create channel')),
                onPressed: () => showCreateChannel(context, widget.serverId),
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.create_new_folder_outlined),
                label: Text(tr('Create category')),
                onPressed: () => showCreateCategory(context, widget.serverId),
              ),
            ],
          ),
        if (canEdit) const SizedBox(height: 12),
        for (var ci = 0; ci < cats.length; ci++) ...[
          Builder(
            builder: (context) {
              final cat = cats[ci];
              final movable = cat.id != 'default';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Gap.md,
                      vertical: Gap.sm,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHigh,
                      borderRadius: br(Radius_.md),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            cat.id == 'default'
                                ? tr('Uncategorized')
                                : cat.title.toUpperCase(),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurfaceVariant,
                              letterSpacing: .5,
                            ),
                          ),
                        ),
                        Text(
                          '${cat.channelIds.length}',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        if (canEdit && movable)
                          upDown(
                            canUp:
                                ci > cats.indexWhere((c) => c.id != 'default'),
                            canDown: ci < cats.length - 1,
                            move: (d) => _moveCategory(ci, d),
                          ),
                      ],
                    ),
                  ),
                  for (var hi = 0; hi < cat.channelIds.length; hi++) ...[
                    Builder(
                      builder: (context) {
                        final cid = cat.channelIds[hi];
                        final ch = store.channels[cid];
                        if (ch == null) return const SizedBox.shrink();
                        final isVoice =
                            ch['channel_type'] == 'VoiceChannel' ||
                            ch['voice'] != null;
                        return Container(
                          margin: const EdgeInsets.only(left: Gap.xl),
                          child: CategoryButton(
                            icon: Icon(
                              isVoice ? Icons.headset_mic_outlined : Icons.tag,
                              size: 20,
                            ),
                            title: Text(store.channelName(ch)),
                            action: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (canEdit)
                                  PopupMenuButton<int>(
                                    tooltip: tr('Move to category'),
                                    icon: const Icon(
                                      Icons.drive_file_move_outline,
                                      size: 20,
                                    ),
                                    onSelected: (to) =>
                                        _moveChannelTo(ci, cid, to),
                                    itemBuilder: (_) => [
                                      for (var ti = 0; ti < cats.length; ti++)
                                        if (ti != ci)
                                          PopupMenuItem(
                                            value: ti,
                                            child: Text(
                                              cats[ti].id == 'default'
                                                  ? tr('Uncategorized')
                                                  : cats[ti].title,
                                            ),
                                          ),
                                    ],
                                  ),
                                if (canEdit)
                                  upDown(
                                    canUp: hi > 0,
                                    canDown: hi < cat.channelIds.length - 1,
                                    move: (d) => _moveChannel(ci, hi, d),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              );
            },
          ),
        ],
        if (canEdit) ...[
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(tr('Save')),
          ),
        ],
      ],
    );
  }
}

/// Server "Discover" settings page — port of the web client's
/// `settings/shared/Discoverable.tsx`.
class _Discoverable extends StatefulWidget {
  const _Discoverable({required this.serverId});
  final String serverId;
  @override
  State<_Discoverable> createState() => _DiscoverableState();
}

class _DiscoverableState extends State<_Discoverable> {
  Map<String, dynamic>? _status;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _status = null;
      _error = null;
    });
    try {
      final r = await context.read<ClientStore>().api.get(
        '/servers/${widget.serverId}/discover',
      );
      if (mounted) {
        setState(
          () => _status = r is Map ? Map<String, dynamic>.from(r) : null,
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _act(String method) => _guard(context, () async {
    setState(() => _busy = true);
    try {
      final api = context.read<ClientStore>().api;
      switch (method) {
        case 'request':
          await api.post('/servers/${widget.serverId}/discover', {});
        case 'cancel':
          await api.delete('/servers/${widget.serverId}/discover');
      }
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final store = context.watch<ClientStore>();
    final server = store.servers[widget.serverId];
    if (server == null) return const SizedBox.shrink();

    Widget preview(String title, String body) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 4,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          Text(
            body,
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );

    Widget submitButton() => CategoryGroup(
      children: [
        CategoryButton(
          icon: const Icon(Icons.public),
          title: Text(tr('Submit to Discover')),
          description: Text(
            tr('Allow others to join your server from Discover'),
          ),
          onTap: _busy ? null : () => _act('request'),
        ),
      ],
    );

    // Already discoverable.
    if (server['discoverable'] == true) {
      return preview(
        tr('This server is discoverable'),
        tr('Contact support to remove this server from discover'),
      );
    }

    if (_status == null && _error != null) {
      return preview(
        tr("Can't get discover request status right now"),
        _error!,
      );
    }
    if (_status == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final status = _status!['status'];
    // NotFound → can request.
    if (_error != null || status == null) return submitButton();
    if (status == 'Pending' || status == 'UnderReview') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          preview(
            tr('Your server is under review'),
            tr('Check back often to see if your server has been approved!'),
          ),
          CategoryGroup(
            children: [
              CategoryButton(
                icon: const Icon(Icons.cancel_outlined),
                title: Text(tr('Cancel discover request')),
                description: Text(
                  tr(
                    'Cancel your discover request and remove it from the review queue',
                  ),
                ),
                onTap: _busy ? null : () => _act('cancel'),
              ),
            ],
          ),
        ],
      );
    }
    if (status is Map && status.containsKey('Denied')) {
      final reason = status['Denied'];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          preview(
            tr('Your discover request has been denied'),
            '${reason != null ? '${tr('Reason:')} $reason\n' : ''}${tr('You can request again below')}',
          ),
          submitButton(),
        ],
      );
    }
    if (status is Map && status.containsKey('Removed')) {
      final reason = status['Removed'];
      return preview(
        tr('Your discover request has been removed'),
        reason != null
            ? '${tr('Reason:')} $reason ${tr('Contact support for more information.')}'
            : '',
      );
    }
    return submitButton();
  }
}
