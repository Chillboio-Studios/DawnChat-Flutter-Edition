import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../api/client_store.dart';
import '../../../core/i18n.dart';
import '../../../theme/tokens.dart';
import '../../widgets.dart';
import '../admin_base.dart';
import '../../modals/app_dialog.dart';


class BotsView extends StatefulWidget {
  const BotsView({super.key});
  @override
  State<BotsView> createState() => _BotsViewState();
}

class _BotsViewState extends State<BotsView> {
  List<Map<String, dynamic>>? _bots;
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
        '/admin/bots',
        query: {
          'limit': '200',
          if (_q.isNotEmpty) 'q': _q,
        },
      ) as List;
      if (mounted) {
        setState(() {
          _bots = r
              .map((e) => (e as Map).cast<String, dynamic>())
              .toList();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _edit(Map<String, dynamic> b) async {
    final owner = await promptText(
      context,
      tr('Change bot owner'),
      label: tr('New owner user ID'),
      initial: b['owner'] as String? ?? '',
    );
    if (owner == null || !mounted) return;
    try {
      await context.read<ClientStore>().api.patch('/admin/bots/${b['id']}', {
        'owner': owner.trim(),
      });
      _load();
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bots = _bots;
    if (bots == null || _error != null) {
      return adminEmptyOrError(_error, bots == null, tr('No bots.'));
    }
    return AdminListScaffold(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.md),
          child: TextField(
            decoration: InputDecoration(
              labelText: tr('Search bots'),
              isDense: true,
            ),
            onSubmitted: (v) {
              setState(() => _q = v.trim());
              _load();
            },
          ),
        ),
        const SizedBox(height: Gap.sm),
        if (bots.isEmpty)
          Center(child: Text(tr('No bots.')))
        else
          for (final b in bots)
            ListTile(
              leading: const Icon(Icons.smart_toy_outlined, size: 20),
              title: Text(
                '${b['username']}#${b['discriminator']}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                'Owner: ${b['owner'] ?? '—'}\n${b['id']}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              isThreeLine: true,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    tooltip: tr('Change owner'),
                    onPressed: () => _edit(b),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20),
                    onSelected: (v) => _botAction(v, b),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'reset_token',
                        child: Text(tr('Reset token')),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          tr('Delete bot'),
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

  Future<void> _botAction(String action, Map<String, dynamic> b) async {
    final api = context.read<ClientStore>().api;
    if (action == 'reset_token') {
      var confirmed = false;
      await showAppDialog<void>(
        context,
        title: tr('Reset bot token?'),
        content: Text(
          tr(
            'This generates a new token for {name} and immediately invalidates the old one. Any running instance of this bot will stop working.',
            {'name': '${b['username']}#${b['discriminator']}'}),
          ),
        actions: [
          DlgAction(tr('Cancel')),
          DlgAction(
            tr('Reset token'),
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
        final res = await api.post('/admin/bots/${b['id']}/reset-token', {})
            as Map;
        if (mounted) {
          final token = '${res['token'] ?? ''}';
          await Clipboard.setData(ClipboardData(text: token));
          showSnack(context, tr('New token copied to clipboard.'));
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
        title: tr('Delete bot permanently?'),
        content: Text(
          tr(
            'This permanently deletes the bot account {name}. This cannot be undone.',
            {'name': '${b['username']}#${b['discriminator']}'}),
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
        await api.delete('/admin/bots/${b['id']}');
        if (mounted) {
          showSnack(context, tr('Bot deleted.'));
          _load();
        }
      } catch (e) {
        if (mounted) showSnack(context, errorText(e));
      }
    }
  }
}

