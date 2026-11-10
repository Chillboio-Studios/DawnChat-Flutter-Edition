import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/client_store.dart';
import '../../api/permissions.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../image_cropper.dart';
import '../widgets.dart';
import '../modals/member_modals.dart';
import '../modals/app_dialog.dart';
import '../../core/i18n.dart';
import 'permission_editor.dart';
import 'settings_page.dart' show SettingsNavRow;

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
    if (c == null) {
      return const Scaffold(body: Center(child: Text('Channel not found')));
    }
    final phone =
        screenClassOf(MediaQuery.sizeOf(context)) == ScreenClass.phone;
    final isServer = c['server'] != null;
    final pages = [
      ('overview', 'Overview', Icons.info_outline),
      if (isServer || c['channel_type'] == 'Group')
        ('permissions', 'Permissions', Icons.lock_outline),
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
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: SettingsNavRow(
              icon: p.$3,
              title: tr(p.$2),
              selected: _page == p.$1,
              onTap: () => setState(() => _page = p.$1),
            ),
          ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: SettingsNavRow(
            icon: Icons.delete_outline,
            title: tr(isServer ? 'Delete Channel' : 'Delete / Leave'),
            selected: false,
            destructive: true,
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
        ),
      ],
    );

    final body = Material(
      clipBehavior: Clip.antiAlias,
      color: cs.surfaceContainerLow,
      borderRadius: phone
          ? BorderRadius.zero
          : const BorderRadius.horizontal(left: Radius.circular(30)),
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
  late int _slowmode =
      (context.read<ClientStore>().channels[widget.channelId]?['slowmode']
              as num?)
          ?.toInt() ??
      0;

  Future<void> _icon({bool remove = false}) async {
    final store = context.read<ClientStore>();
    try {
      final body = <String, dynamic>{};
      if (remove) {
        body['remove'] = ['Icon'];
      } else {
        final file = await pickImageForUpload(
          context,
          shape: CropShape.rect,
          name: 'icon',
        );
        if (file == null) return;
        body['icon'] = await store.api.uploadFile(
          'icons',
          file.name,
          mimeFromNameSimple(file.name),
          file.bytes,
        );
      }
      final response = await store.api.patch(
        '/channels/${widget.channelId}',
        body,
      );
      if (response is Map)
        store.channels[widget.channelId]!.addAll(
          response.cast<String, dynamic>(),
        );
      if (remove) store.channels[widget.channelId]!.remove('icon');
      store.refresh();
    } catch (error) {
      if (mounted) showSnack(context, errorText(error));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconAvatar(
              url: store.api.fileUrl(
                'icons',
                store.channels[widget.channelId]?['icon'] as Map?,
                width: 96,
              ),
              name: _name.text,
              size: 48,
            ),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.upload),
              label: Text(tr('Channel Icon')),
              onPressed: _icon,
            ),
            if (store.channels[widget.channelId]?['icon'] != null)
              IconButton(
                tooltip: tr('Remove'),
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _icon(remove: true),
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          maxLength: 32,
          decoration: InputDecoration(labelText: tr('Channel Name')),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _desc,
          minLines: 3,
          maxLines: 8,
          maxLength: 1024,
          decoration: InputDecoration(labelText: tr('Channel Description')),
        ),
        const SizedBox(height: 8),
        if (store.channels[widget.channelId]?['channel_type'] == 'TextChannel')
          DropdownButtonFormField<int>(
            initialValue: _slowmode,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('Channel Slowmode')),
            items: [
              for (final seconds in {
                0,
                5,
                10,
                30,
                60,
                300,
                600,
                1800,
                3600,
                7200,
                21600,
                _slowmode,
              })
                DropdownMenuItem(
                  value: seconds,
                  child: Text(seconds == 0 ? tr('Slowmode off') : '$seconds s'),
                ),
            ],
            onChanged: (next) => setState(() => _slowmode = next ?? 0),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Age-restricted (NSFW)'),
          value: _nsfw,
          onChanged: (v) => setState(() => _nsfw = v),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () async {
            if (_name.text.trim().isEmpty) return;
            try {
              final body = <String, dynamic>{
                'name': _name.text.trim(),
                if (_desc.text.trim().isNotEmpty)
                  'description': _desc.text.trim(),
                if (_desc.text.trim().isEmpty) 'remove': ['Description'],
                'nsfw': _nsfw,
                'slowmode': _slowmode,
              };
              await store.api.patch('/channels/${widget.channelId}', body);
              store.channels[widget.channelId]!.addAll({
                'name': _name.text.trim(),
                'description': _desc.text.trim(),
                'nsfw': _nsfw,
                'slowmode': _slowmode,
              });
              store.refresh();
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
  String target = 'default';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final channel = store.channels[widget.channelId]!;
    final group = channel['channel_type'] == 'Group';
    final roles = (store.servers[channel['server']]?['roles'] as Map?) ?? {};
    final initial = group
        ? channel['permissions'] ?? Perm.dmDefault.toInt()
        : target == 'default'
        ? channel['default_permissions']
        : (channel['role_permissions'] as Map?)?[target];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!group)
          DropdownButtonFormField<String>(
            initialValue: target,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('Role Overrides')),
            items: [
              DropdownMenuItem(value: 'default', child: Text(tr('Everyone'))),
              for (final role in roles.entries)
                DropdownMenuItem(
                  value: role.key as String,
                  child: Text((role.value as Map)['name'] as String? ?? ''),
                ),
            ],
            onChanged: (next) => setState(() => target = next ?? 'default'),
          ),
        PermissionSettings(
          key: ValueKey(target),
          initial: initial,
          overrides: !group,
          server: false,
          onSave: (value) async {
            await store.api.put(
              '/channels/${widget.channelId}/permissions/$target',
              {'permissions': group ? value.allow.toInt() : value.payload},
            );
            if (group) {
              channel['permissions'] = value.allow.toInt();
            } else if (target == 'default') {
              channel['default_permissions'] = value.cached;
            } else {
              ((channel['role_permissions'] ??= <String, dynamic>{})
                      as Map)[target] =
                  value.cached;
            }
            store.refresh();
          },
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

  Future<void> _edit(Map<String, dynamic> webhook) async {
    final store = context.read<ClientStore>();
    final name = TextEditingController(text: webhook['name'] as String? ?? '');
    PickedImage? avatar;
    bool remove = false;
    try {
      await showAppDialog<void>(
        context,
        title: tr('Edit Webhook'),
        content: StatefulBuilder(
          builder: (context, update) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                maxLength: 32,
                decoration: InputDecoration(labelText: tr('Webhook Name')),
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.upload),
                    label: Text(avatar?.name ?? tr('Webhook Icon')),
                    onPressed: () async {
                      final picked = await pickImageForUpload(
                        context,
                        shape: CropShape.circle,
                        name: 'avatar',
                      );
                      if (context.mounted && picked != null)
                        update(() {
                          avatar = picked;
                          remove = false;
                        });
                    },
                  ),
                  IconButton(
                    tooltip: tr('Remove'),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => update(() {
                      avatar = null;
                      remove = true;
                    }),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          DlgAction(tr('Cancel')),
          DlgAction(
            tr('Save'),
            onPressed: () async {
              if (name.text.trim().isEmpty) return false;
              final body = <String, dynamic>{'name': name.text.trim()};
              if (avatar != null) {
                body['avatar'] = await store.api.uploadFile(
                  'avatars',
                  avatar!.name,
                  mimeFromNameSimple(avatar!.name),
                  avatar!.bytes,
                );
              } else if (remove) {
                body['remove'] = ['Avatar'];
              }
              await store.api.patch(
                '/webhooks/${webhook['id'] ?? webhook['_id']}',
                body,
              );
              if (mounted) await _load();
              return null;
            },
          ),
        ],
      );
    } finally {
      name.dispose();
    }
  }

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
      if (mounted) {
        setState(
          () =>
              _list = r.map((e) => (e as Map).cast<String, dynamic>()).toList(),
        );
      }
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
                  onTap: () => _edit(w),
                  description: Text(w['id'] as String? ?? ''),
                  action: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: tr('Edit Webhook'),
                        onPressed: () => _edit(w),
                      ),
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
