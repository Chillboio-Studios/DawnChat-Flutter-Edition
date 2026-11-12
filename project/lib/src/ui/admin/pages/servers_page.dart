import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../api/client_store.dart';
import '../../../core/i18n.dart';
import '../../../theme/tokens.dart';
import '../../widgets.dart';
import '../../modals/app_dialog.dart';
import '../admin_base.dart';


class ServersView extends StatefulWidget {
  const ServersView({super.key});
  @override
  State<ServersView> createState() => _ServersViewState();
}

class _ServersViewState extends State<ServersView> {
  List<Map<String, dynamic>>? _servers;
  String? _error;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final store = context.read<ClientStore>();
      final r = await store.api.get(
        '/admin/servers',
        query: {
          'limit': '200',
          if (_q.isNotEmpty) 'q': _q,
        },
      ) as List;
      if (mounted) {
        setState(() {
          _servers = r
              .map((e) => (e as Map).cast<String, dynamic>())
              .toList();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _edit(Map<String, dynamic> s) async {
    final name = TextEditingController(text: s['name'] as String? ?? '');
    final desc = TextEditingController(
      text: s['description'] as String? ?? '',
    );
    var discoverable = s['discoverable'] == true;
    var nsfw = s['nsfw'] == true;
    var analytics = s['analytics'] == true;
    final saved = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(tr('Edit server')),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: InputDecoration(labelText: tr('Name'), isDense: true),
                ),
                const SizedBox(height: Gap.sm),
                TextField(
                  controller: desc,
                  decoration: InputDecoration(
                    labelText: tr('Description'),
                    isDense: true,
                  ),
                  maxLines: 3,
                ),
                CheckboxListTile(
                  value: discoverable,
                  onChanged: (v) => set(() => discoverable = v ?? false),
                  title: Text(tr('Discoverable')),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                CheckboxListTile(
                  value: nsfw,
                  onChanged: (v) => set(() => nsfw = v ?? false),
                  title: Text(tr('NSFW')),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                CheckboxListTile(
                  value: analytics,
                  onChanged: (v) => set(() => analytics = v ?? false),
                  title: Text(tr('Analytics')),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(tr('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(tr('Save')),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;
    try {
      await context.read<ClientStore>().api.patch('/admin/servers/${s['id']}', {
        'name': name.text.trim(),
        'description': desc.text.trim(),
        'discoverable': discoverable,
        'nsfw': nsfw,
        'analytics': analytics,
      });
      _load();
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final servers = _servers;
    if (servers == null || _error != null) {
      return adminEmptyOrError(_error, servers == null, tr('No servers.'));
    }
    return AdminListScaffold(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.md),
          child: TextField(
            decoration: InputDecoration(
              labelText: tr('Search servers'),
              isDense: true,
            ),
            onSubmitted: (v) {
              setState(() => _q = v.trim());
              _load();
            },
          ),
        ),
        const SizedBox(height: Gap.sm),
        if (servers.isEmpty)
          Center(child: Text(tr('No servers.')))
        else
          for (final s in servers)
            ListTile(
              leading: const Icon(Icons.dns_outlined, size: 20),
              title: Text(
                s['name'] as String? ?? '',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '${s['id']}\n'
                '${s['channel_count'] ?? 0} channels · ${s['role_count'] ?? 0} roles'
                '${s['nsfw'] == true ? ' · NSFW' : ''}'
                '${s['discoverable'] == true ? ' · Discoverable' : ''}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              isThreeLine: true,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    onPressed: () => _edit(s),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20),
                    onSelected: (v) => _serverAction(v, s),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'transfer',
                        child: Text(tr('Transfer ownership')),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          tr('Delete server'),
                          style: TextStyle(color: context.cs.error),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
      ],
    );
  }

  Future<void> _serverAction(String action, Map<String, dynamic> s) async {
    final api = context.read<ClientStore>().api;
    if (action == 'transfer') {
      final ctrl = TextEditingController();
      var confirmed = false;
      await showAppDialog<void>(
        context,
        title: tr('Transfer ownership'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr('New owner user ID for “{name}”.', {'name': '${s['name']}'})),
            const SizedBox(height: Gap.sm),
            TextField(
              controller: ctrl,
              decoration: InputDecoration(
                labelText: tr('User ID'),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          DlgAction(tr('Cancel')),
          DlgAction(
            tr('Transfer'),
            onPressed: () async {
              if (ctrl.text.trim().isEmpty) return false;
              confirmed = true;
              return true;
            },
          ),
        ],
      );
      if (!confirmed || !mounted) return;
      try {
        await api.post('/admin/servers/${s['id']}/transfer', {
          'user_id': ctrl.text.trim(),
        });
        if (mounted) {
          showSnack(context, tr('Ownership transferred.'));
          _load();
        }
      } catch (e) {
        if (mounted) showSnack(context, errorText(e));
      }
      return;
    }
    if (action == 'delete') {
      var confirmed = false;
      await showAppDialog<void>(
        context,
        title: tr('Delete server permanently?'),
        content: Text(
          tr(
            'This permanently deletes “{name}” and all its channels, messages, roles and members data. This cannot be undone.',
            {'name': '${s['name']}'}),
          ),
        actions: [
          DlgAction(tr('Cancel')),
          DlgAction(
            tr('Delete permanently'),
            destructive: true,
            onPressed: () async {
              confirmed = true;
              return true;
            },
          ),
        ],
      );
      if (!confirmed || !mounted) return;
      try {
        await api.delete('/admin/servers/${s['id']}');
        if (mounted) {
          showSnack(context, tr('Server deleted.'));
          _load();
        }
      } catch (e) {
        if (mounted) showSnack(context, errorText(e));
      }
    }
  }
}

