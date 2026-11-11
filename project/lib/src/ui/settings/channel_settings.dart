import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/client_store.dart';
import '../../api/permissions.dart';
import '../../core/css_colour.dart';
import '../net_image.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../image_cropper.dart';
import '../widgets.dart';
import '../modals/member_modals.dart';
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
    final type = c['channel_type'] as String? ?? '';
    final isServer = c['server'] != null;
    final isGroup = type == 'Group';
    // Mirrors the web client's `ChannelSettings.list()` visibility rules.
    final canManagePermissions = isServer
        ? store.canInServer(c['server'] as String, Perm.managePermissions)
        : store.can(widget.channelId, Perm.managePermissions);
    final canManageChannel = isServer
        ? store.canInServer(c['server'] as String, Perm.manageChannel)
        : store.can(widget.channelId, Perm.manageChannel);
    final pages = [
      ('overview', 'Overview', Icons.info_outline),
      if (type != 'SavedMessages' && canManagePermissions)
        ('permissions', 'Permissions', Icons.lock_outline),
      if (isServer) ('webhooks', 'Webhooks', Icons.webhook_outlined),
    ];
    // Web only offers delete for non-Group channels with ManageChannel.
    final showDelete = !isGroup && canManageChannel;

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
        if (showDelete)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: SettingsNavRow(
              icon: Icons.delete_outline,
              title: tr('Delete Channel'),
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
    final channel = store.channels[widget.channelId]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('Channel Info'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconAvatar(
              url: store.api.fileUrl(
                'icons',
                channel['icon'] as Map?,
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
            if (channel['icon'] != null)
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
          minLines: 2,
          maxLines: 8,
          maxLength: 1024,
          decoration: InputDecoration(
            labelText: tr('Channel Description'),
            hintText: tr('This channel is about...'),
          ),
        ),
        const SizedBox(height: 8),
        if (channel['channel_type'] == 'TextChannel')
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
                  child: Text(_slowmodeLabel(seconds)),
                ),
            ],
            onChanged: (next) => setState(() => _slowmode = next ?? 0),
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            TextButton(
              onPressed: () => setState(() {
                _name.text = channel['name'] as String? ?? '';
                _desc.text = channel['description'] as String? ?? '';
                _nsfw = channel['nsfw'] == true;
                _slowmode = (channel['slowmode'] as num?)?.toInt() ?? 0;
              }),
              child: Text(tr('Reset')),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => _save(context, channel),
              child: Text(tr('Save')),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 16),
        Text(
          tr('Mark as Mature'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          tr(
            'Users will be asked to confirm their age before opening this channel.',
          ),
          style: TextStyle(fontSize: 13, color: context.cs.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        FilledButton.tonal(
          onPressed: () async {
            final mature = channel['nsfw'] == true;
            if (!await confirm(
              context,
              mature
                  ? tr('Unmark this channel as mature?')
                  : tr('Mark this channel as mature?'),
              '',
              action: mature ? tr('Unmark as mature') : tr('Mark as mature'),
            )) {
              return;
            }
            try {
              await store.api.patch('/channels/${widget.channelId}', {
                'nsfw': !mature,
              });
              channel['nsfw'] = !mature;
              store.refresh();
            } catch (e) {
              if (context.mounted) showSnack(context, errorText(e));
            }
          },
          child: Text(
            channel['nsfw'] == true
                ? tr('Unmark as Mature')
                : tr('Mark as Mature'),
          ),
        ),
      ],
    );
  }

  String _slowmodeLabel(int seconds) {
    if (seconds == 0) return tr('Slowmode off');
    if (seconds < 60) return tr('${seconds}s');
    final minutes = seconds ~/ 60;
    if (minutes < 60) return tr('${minutes}m');
    final hours = minutes ~/ 60;
    return tr('${hours}h');
  }

  Future<void> _save(BuildContext context, Map<String, dynamic> channel) async {
    if (_name.text.trim().isEmpty) return;
    try {
      final body = <String, dynamic>{
        'name': _name.text.trim(),
        if (_desc.text.trim().isNotEmpty) 'description': _desc.text.trim(),
        if (_desc.text.trim().isEmpty) 'remove': ['Description'],
        'nsfw': _nsfw,
        'slowmode': _slowmode,
      };
      await context.read<ClientStore>().api.patch(
        '/channels/${widget.channelId}',
        body,
      );
      channel.addAll({
        'name': _name.text.trim(),
        'description': _desc.text.trim(),
        'nsfw': _nsfw,
        'slowmode': _slowmode,
      });
      context.read<ClientStore>().refresh();
      if (context.mounted) showSnack(context, 'Saved');
    } catch (e) {
      if (context.mounted) showSnack(context, errorText(e));
    }
  }
}

class _Permissions extends StatefulWidget {
  const _Permissions({required this.channelId});
  final String channelId;
  @override
  State<_Permissions> createState() => _PermissionsState();
}

class _PermissionsState extends State<_Permissions> {
  // 'overview' | 'default' | <roleId> — mirrors the web client's
  // ChannelPermissionsOverview + permissions/<target> sub-pages.
  String target = 'overview';

  static int _bitCount(int v) {
    var bits = 0;
    for (var i = 0; i < 64; i++) {
      if ((v >> i) & 1 == 1) bits++;
    }
    return bits;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final channel = store.channels[widget.channelId]!;
    final group = channel['channel_type'] == 'Group';
    final server = store.servers[channel['server'] as String? ?? ''];
    final roles = ((server?['roles'] as Map?) ?? const {})
        .cast<String, dynamic>();

    // Group channels edit permissions directly (web `type="group"` editor).
    if (group) {
      return _editor(channel, roles, 'default', group: true);
    }

    if (target != 'overview') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            onPressed: () => setState(() => target = 'overview'),
            icon: const Icon(Icons.arrow_back),
            label: Text(tr('Permissions')),
          ),
          _editor(channel, roles, target),
        ],
      );
    }

    // Ordered roles, split into those with and without overrides —
    // mirrors `ChannelPermissionsOverview.tsx`.
    final ordered = roles.keys.toList()
      ..sort((a, b) {
        final ra = ((roles[a] as Map)['rank'] as num?)?.toInt() ?? 0;
        final rb = ((roles[b] as Map)['rank'] as num?)?.toInt() ?? 0;
        return ra != rb ? ra.compareTo(rb) : a.compareTo(b);
      });
    Map<String, dynamic>? overrideOf(String roleId) {
      final o = (channel['role_permissions'] as Map?)?[roleId];
      return o is Map ? o.cast<String, dynamic>() : null;
    }

    final withOverrides = <String>[], without = <String>[];
    for (final id in ordered) {
      final o = overrideOf(id);
      final allow = (o?['a'] as num?)?.toInt() ?? 0;
      final deny = (o?['d'] as num?)?.toInt() ?? 0;
      (allow != 0 || deny != 0 ? withOverrides : without).add(id);
    }

    Widget roleButton(String id, String? description) => CategoryButton(
      icon: _RoleDot(colour: (roles[id] as Map?)?['colour'] as String?),
      title: Text((roles[id] as Map?)?['name'] as String? ?? ''),
      description: description == null ? null : Text(description),
      action: const Icon(Icons.chevron_right),
      onTap: () => setState(() => target = id),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 16,
      children: [
        CategoryButton(
          icon: const Icon(Icons.public),
          title: Text(tr('Everyone')),
          description: Text(
            tr('Permissions available when no role overrides apply'),
          ),
          action: const Icon(Icons.chevron_right),
          onTap: () => setState(() => target = 'default'),
        ),
        Text(
          tr('Role Overrides').toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: context.cs.outline,
          ),
        ),
        if (withOverrides.isEmpty)
          Text(
            tr('No role overrides have been configured.'),
            style: TextStyle(color: context.cs.onSurfaceVariant),
          )
        else
          for (final id in withOverrides)
            roleButton(
              id,
              tr(
                'Grants ${_bitCount((overrideOf(id)?['a'] as num?)?.toInt() ?? 0)} permissions and denies ${_bitCount((overrideOf(id)?['d'] as num?)?.toInt() ?? 0)} permissions',
              ),
            ),
        Text(
          tr('Roles with No Overrides').toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: context.cs.outline,
          ),
        ),
        if (without.isEmpty)
          Text(
            tr('All roles have overrides.'),
            style: TextStyle(color: context.cs.onSurfaceVariant),
          )
        else
          for (final id in without)
            roleButton(id, tr('No permissions set yet')),
      ],
    );
  }

  Widget _editor(
    Map<String, dynamic> channel,
    Map<String, dynamic> roles,
    String target, {
    bool group = false,
  }) {
    final store = context.read<ClientStore>();
    final initial = group
        ? channel['permissions'] ?? Perm.dmDefault.toInt()
        : target == 'default'
        ? channel['default_permissions']
        : (channel['role_permissions'] as Map?)?[target];
    final title = target == 'default'
        ? tr('Everyone')
        : (roles[target] as Map?)?['name'] as String? ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        PermissionSettings(
          key: ValueKey('$group-$target'),
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

class _RoleDot extends StatelessWidget {
  const _RoleDot({this.colour});
  final String? colour;
  @override
  Widget build(BuildContext context) {
    final c = colour == null ? null : parseCssColour(colour!);
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
        border: c == null
            ? Border.all(color: context.cs.outline, style: BorderStyle.solid)
            : null,
      ),
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
  // Selected webhook id — mirrors the web `webhooks/<id>` sub-page.
  String? _viewing;

  Map<String, dynamic>? get _viewingWebhook {
    for (final w in _list ?? const <Map<String, dynamic>>[]) {
      if ((w['id'] ?? w['_id']) == _viewing) return w;
    }
    return null;
  }

  Future<void> _create() async {
    final store = context.read<ClientStore>();
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
      await _load();
    } catch (e) {
      if (context.mounted) showSnack(context, errorText(e));
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

    final viewing = _viewingWebhook;
    if (viewing != null) {
      return _WebhookView(
        key: ValueKey(_viewing),
        webhook: viewing,
        onBack: () => setState(() => _viewing = null),
        onChanged: _load,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CategoryButton(
          icon: const Icon(Icons.cloud_outlined),
          title: Text(tr('Create Webhook')),
          action: const Icon(Icons.chevron_right),
          onTap: _create,
        ),
        const SizedBox(height: 16),
        if (list.isEmpty)
          Text(
            tr('No webhooks.'),
            style: TextStyle(color: context.cs.onSurfaceVariant),
          )
        else
          CategoryGroup(
            children: [
              for (final w in list)
                CategoryButton(
                  icon: w['avatar'] != null
                      ? NetImage(
                          store.api.fileUrl(
                                'avatars',
                                w['avatar'] as Map?,
                                width: 48,
                              ) ??
                              '',
                          width: 24,
                          height: 24,
                        )
                      : const Icon(Icons.webhook_outlined, size: 24),
                  title: Text(w['name'] as String? ?? 'Webhook'),
                  description: Text(w['id'] as String? ?? ''),
                  action: const Icon(Icons.chevron_right),
                  onTap: () => setState(
                    () => _viewing = (w['id'] ?? w['_id']) as String,
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// Webhook detail page — mirrors `ViewWebhook.tsx`: avatar + name form with
/// Reset/Save, then Copy webhook URL and Delete webhook actions.
class _WebhookView extends StatefulWidget {
  const _WebhookView({
    super.key,
    required this.webhook,
    required this.onBack,
    required this.onChanged,
  });
  final Map<String, dynamic> webhook;
  final VoidCallback onBack;
  final Future<void> Function() onChanged;

  @override
  State<_WebhookView> createState() => _WebhookViewState();
}

class _WebhookViewState extends State<_WebhookView> {
  late final _name = TextEditingController(
    text: widget.webhook['name'] as String? ?? '',
  );
  PickedImage? _avatar;
  bool _removeAvatar = false, _busy = false;

  String get _id => (widget.webhook['id'] ?? widget.webhook['_id']) as String;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _reset() => setState(() {
    _name.text = widget.webhook['name'] as String? ?? '';
    _avatar = null;
    _removeAvatar = false;
  });

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final store = context.read<ClientStore>();
      final body = <String, dynamic>{'name': _name.text.trim()};
      if (_avatar != null) {
        body['avatar'] = await store.api.uploadFile(
          'avatars',
          _avatar!.name,
          mimeFromNameSimple(_avatar!.name),
          _avatar!.bytes,
        );
      } else if (_removeAvatar) {
        body['remove'] = ['Avatar'];
      }
      await store.api.patch('/webhooks/$_id', body);
      widget.webhook['name'] = _name.text.trim();
      if (_removeAvatar) widget.webhook.remove('avatar');
      await widget.onChanged();
      if (mounted) showSnack(context, 'Saved');
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<ClientStore>();
    final webhook = widget.webhook;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 16,
      children: [
        TextButton.icon(
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back),
          label: Text(tr('Webhooks')),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (_avatar != null)
              ClipOval(
                child: Image.memory(_avatar!.bytes, width: 48, height: 48),
              )
            else if (webhook['avatar'] != null && !_removeAvatar)
              NetImage(
                store.api.fileUrl(
                      'avatars',
                      webhook['avatar'] as Map?,
                      width: 96,
                    ) ??
                    '',
                width: 48,
                height: 48,
              )
            else
              const Icon(Icons.webhook_outlined, size: 48),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.upload),
              label: Text(tr('Webhook Icon')),
              onPressed: _busy
                  ? null
                  : () async {
                      final picked = await pickImageForUpload(
                        context,
                        shape: CropShape.circle,
                        name: 'avatar',
                      );
                      if (mounted && picked != null)
                        setState(() {
                          _avatar = picked;
                          _removeAvatar = false;
                        });
                    },
            ),
            if (webhook['avatar'] != null || _avatar != null)
              IconButton(
                tooltip: tr('Remove'),
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _avatar = null;
                        _removeAvatar = true;
                      }),
                icon: const Icon(Icons.delete_outline),
              ),
          ],
        ),
        TextField(
          controller: _name,
          maxLength: 32,
          decoration: InputDecoration(labelText: tr('Webhook Name')),
        ),
        Row(
          children: [
            TextButton(
              onPressed: _busy ? null : _reset,
              child: Text(tr('Reset')),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(tr('Save')),
            ),
          ],
        ),
        CategoryButton(
          icon: const Icon(Icons.copy),
          title: Text(tr('Copy webhook URL')),
          action: const Icon(Icons.chevron_right),
          onTap: () => copyText(
            context,
            '${store.api.baseUrl}/webhooks/$_id/${webhook['token']}',
          ),
        ),
        CategoryButton(
          icon: const Icon(Icons.delete_outline),
          title: Text(tr('Delete webhook')),
          action: const Icon(Icons.chevron_right),
          onTap: () async {
            if (!await confirm(
              context,
              tr('Delete webhook'),
              webhook['name'] as String? ?? '',
              action: tr('Delete'),
            )) {
              return;
            }
            try {
              await store.api.delete('/webhooks/$_id');
              await widget.onChanged();
              widget.onBack();
            } catch (e) {
              if (context.mounted) showSnack(context, errorText(e));
            }
          },
        ),
      ],
    );
  }
}
