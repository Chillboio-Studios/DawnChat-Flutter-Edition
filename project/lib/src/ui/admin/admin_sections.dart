import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../api/client_store.dart';
import '../../api/transport.dart';
import '../../core/i18n.dart';
import '../../theme/tokens.dart';
import '../modals/app_dialog.dart';
import '../widgets.dart';

/// Shared list scaffold for admin sections.
class AdminListScaffold extends StatelessWidget {
  const AdminListScaffold({
    super.key,
    required this.children,
    this.trailing,
  });
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (trailing != null)
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.all(Gap.md),
            child: trailing,
          ),
        ),
      Expanded(child: ListView(children: children)),
    ],
  );
}

Widget _emptyOrError(String? error, bool loading, String empty) {
  if (error != null) return Center(child: Text(error));
  if (loading) return const Center(child: CircularProgressIndicator());
  return Center(child: Text(empty));
}

// ---------------- Audit Log ----------------

class AuditView extends StatefulWidget {
  const AuditView({super.key});
  @override
  State<AuditView> createState() => _AuditViewState();
}

class _AuditViewState extends State<AuditView> {
  List<Map<String, dynamic>>? _entries;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await context.read<ClientStore>().api.get(
        '/admin/audit-logs',
        query: {'limit': '200'},
      ) as List;
      if (mounted) {
        setState(() {
          _entries = r
              .map((e) => (e as Map).cast<String, dynamic>())
              .toList();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    if (entries == null || _error != null) {
      return _emptyOrError(_error, entries == null, tr('No audit entries.'));
    }
    if (entries.isEmpty) {
      return _emptyOrError(null, false, tr('No audit entries.'));
    }
    String esc(Object? v) {
      final s = '$v';
      return s.contains(',') || s.contains('"') || s.contains('\n')
          ? '"${s.replaceAll('"', '""')}"'
          : s;
    }

    Future<void> exportCsv() async {
      final buf = StringBuffer(
        'created_at,action,target_type,target_id,actor_id,details\n',
      );
      for (final e in entries) {
        buf.writeln(
          [
            e['created_at'],
            e['action'],
            e['target_type'],
            e['target_id'],
            e['actor_id'],
            e['details'],
          ].map(esc).join(','),
        );
      }
      await Clipboard.setData(ClipboardData(text: buf.toString()));
      if (context.mounted) {
        showSnack(context, tr('Audit log CSV copied to clipboard.'));
      }
    }

    return AdminListScaffold(
      children: [
        Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: exportCsv,
              icon: const Icon(Icons.download_outlined, size: 18),
              label: Text(tr('Export CSV')),
            ),
          ),
        ),
        for (final e in entries)
          ListTile(
            dense: true,
            leading: const Icon(Icons.history, size: 20),
            title: Text(
              '${e['action']}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              [
                if (e['target_type'] != null) '${e['target_type']}',
                if (e['target_id'] != null) '${e['target_id']}',
                if (e['details'] != null && '${e['details']}'.isNotEmpty)
                  '${e['details']}',
                'by ${e['actor_id']}',
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(
              (e['created_at'] as String? ?? '').split('T').first,
              style: const TextStyle(fontSize: 12),
            ),
          ),
      ],
    );
  }
}

// ---------------- Safety Strikes ----------------

class StrikesView extends StatefulWidget {
  const StrikesView({super.key});
  @override
  State<StrikesView> createState() => _StrikesViewState();
}

class _StrikesViewState extends State<StrikesView> {
  List<Map<String, dynamic>>? _strikes;
  String? _error;
  String _userFilter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final store = context.read<ClientStore>();
      final r = await store.api.get(
        '/admin/strikes',
        query: {
          'limit': '200',
          if (_userFilter.isNotEmpty) 'user_id': _userFilter,
        },
      ) as List;
      if (mounted) {
        setState(() {
          _strikes = r
              .map((e) => (e as Map).cast<String, dynamic>())
              .toList();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _issue() async {
    final userId = await promptText(context, tr('Issue strike'), label: tr('User ID'));
    if (userId == null || userId.trim().isEmpty || !mounted) return;
    final reason = await promptText(context, tr('Reason'), label: tr('Reason'));
    if (reason == null || !mounted) return;
    try {
      await context.read<ClientStore>().api.post('/admin/strikes', {
        'user_id': userId.trim(),
        'reason': reason.trim(),
      });
      _load();
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    }
  }

  Future<void> _delete(Map<String, dynamic> s) async {
    final ok = await confirm(context, 'Delete strike?', 'This cannot be undone.', action: 'Delete');
    if (!ok || !mounted) return;
    try {
      await context.read<ClientStore>().api.delete('/admin/strikes/${s['id']}');
      _load();
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final strikes = _strikes;
    if (strikes == null || _error != null) {
      return _emptyOrError(_error, strikes == null, tr('No strikes.'));
    }
    return AdminListScaffold(
      trailing: FilledButton.icon(
        onPressed: _issue,
        icon: const Icon(Icons.add, size: 18),
        label: Text(tr('Issue strike')),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.md),
          child: TextField(
            decoration: InputDecoration(
              labelText: tr('Filter by user ID'),
              isDense: true,
              suffixIcon: _userFilter.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        setState(() => _userFilter = '');
                        _load();
                      },
                    )
                  : null,
            ),
            onSubmitted: (v) {
              setState(() => _userFilter = v.trim());
              _load();
            },
          ),
        ),
        const SizedBox(height: Gap.sm),
        if (strikes.isEmpty)
          Center(child: Text(tr('No strikes.')))
        else
          for (final s in strikes)
            ListTile(
              leading: const Icon(Icons.gavel_outlined, size: 20),
              title: Text(
                'User ${s['user_id']}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '${s['reason'] ?? ''}\nby ${s['issued_by']} · ${(s['issued_at'] as String? ?? '').split('T').first}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              isThreeLine: true,
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () => _delete(s),
              ),
            ),
      ],
    );
  }
}

// ---------------- Servers ----------------

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
      return _emptyOrError(_error, servers == null, tr('No servers.'));
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

// ---------------- Bots ----------------

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
      return _emptyOrError(_error, bots == null, tr('No bots.'));
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

// ---------------- Announce ----------------

class AnnounceView extends StatefulWidget {
  const AnnounceView({super.key});
  @override
  State<AnnounceView> createState() => _AnnounceViewState();
}

class _AnnounceViewState extends State<AnnounceView> {
  final _content = TextEditingController();
  final _channel = TextEditingController();
  final _users = TextEditingController();
  final _sendAt = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _content.dispose();
    _channel.dispose();
    _users.dispose();
    _sendAt.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final content = _content.text.trim();
    if (content.isEmpty) {
      showSnack(context, tr('Message cannot be empty.'));
      return;
    }
    final channelId = _channel.text.trim();
    final userIds = _users.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (channelId.isEmpty && userIds.isEmpty) {
      showSnack(context, tr('Provide a channel ID or user IDs.'));
      return;
    }
    setState(() => _sending = true);
    try {
      final res = await context.read<ClientStore>().api.post('/admin/announce', {
        'content': content,
        if (channelId.isNotEmpty) 'channel_id': channelId,
        if (userIds.isNotEmpty) 'user_ids': userIds,
        if (_sendAt.text.trim().isNotEmpty) 'send_at': _sendAt.text.trim(),
      }) as Map;
      if (mounted) {
        showSnack(
          context,
          res['scheduled'] == true
              ? tr('Announcement scheduled.')
              : tr('Sent to {n} recipient(s).', {
                  'n': res['sent'] ?? 0,
                }),
        );
        _content.clear();
      }
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminListScaffold(
      children: [
        Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('Post an announcement as the system account.'),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: Gap.md),
              TextField(
                controller: _content,
                maxLines: 5,
                minLines: 3,
                decoration: InputDecoration(
                  labelText: tr('Message'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: Gap.sm),
              TextField(
                controller: _channel,
                decoration: InputDecoration(
                  labelText: tr('Channel ID (optional if DMing users)'),
                  isDense: true,
                ),
              ),
              const SizedBox(height: Gap.sm),
              TextField(
                controller: _users,
                decoration: InputDecoration(
                  labelText: tr('User IDs to DM (comma-separated, optional)'),
                  isDense: true,
                ),
              ),
              const SizedBox(height: Gap.sm),
              TextField(
                controller: _sendAt,
                decoration: InputDecoration(
                  labelText: tr('Send at (ISO-8601, optional — e.g. 2025-01-01T12:00:00Z)'),
                  hintText: tr('Leave empty to send now'),
                  isDense: true,
                ),
              ),
              const SizedBox(height: Gap.md),
              FilledButton.icon(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.campaign_outlined, size: 18),
                label: Text(tr('Send announcement')),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------- Overview ----------------

class OverviewView extends StatefulWidget {
  const OverviewView({super.key});
  @override
  State<OverviewView> createState() => _OverviewViewState();
}

class _OverviewViewState extends State<OverviewView> {
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>>? _recent;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<ClientStore>().api;
    try {
      final stats = await api.get('/admin/overview') as Map;
      final audit = await api.get(
        '/admin/audit-logs',
        query: {'limit': '10'},
      ) as List;
      if (mounted) {
        setState(() {
          _stats = stats.cast<String, dynamic>();
          _recent = audit
              .map((e) => (e as Map).cast<String, dynamic>())
              .toList();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    if (stats == null || _error != null) {
      return _emptyOrError(_error, stats == null, tr('No data.'));
    }
    final cards = <(String, String, IconData)>[
      ('users', tr('Users'), Icons.people_outline),
      ('servers', tr('Servers'), Icons.dns_outlined),
      ('open_reports', tr('Open reports'), Icons.flag_outlined),
      ('total_reports', tr('Total reports'), Icons.assignment_outlined),
      ('strikes', tr('Safety strikes'), Icons.gavel_outlined),
      ('active_bans', tr('Active bans'), Icons.block_outlined),
      ('pending_shield_scans', tr('Pending Shield scans'), Icons.shield_outlined),
    ];
    return AdminListScaffold(
      children: [
        Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Wrap(
            spacing: Gap.md,
            runSpacing: Gap.md,
            children: [
              for (final c in cards)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(Gap.lg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(c.$3, size: 28),
                        const SizedBox(height: Gap.sm),
                        Text(
                          '${stats[c.$1] ?? 0}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(c.$2, style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Text(
            tr('Recent activity'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        for (final e in _recent ?? const <Map<String, dynamic>>[])
          ListTile(
            dense: true,
            leading: const Icon(Icons.history, size: 20),
            title: Text('${e['action']}'),
            subtitle: Text(
              '${e['target_type'] ?? ''} ${e['target_id'] ?? ''} — by ${e['actor_id'] ?? ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(
              (e['created_at'] as String? ?? '').split('T').first,
              style: const TextStyle(fontSize: 12),
            ),
          ),
      ],
    );
  }
}

// ---------------- Universal ID Lookup ----------------

class LookupView extends StatefulWidget {
  const LookupView({super.key});
  @override
  State<LookupView> createState() => _LookupViewState();
}

class _LookupViewState extends State<LookupView> {
  final _id = TextEditingController();
  Map<String, dynamic>? _result;
  bool _loading = false;
  String? _error;

  Future<void> _lookup() async {
    final id = _id.text.trim();
    if (id.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final r = await context.read<ClientStore>().api.get(
        '/admin/lookup/${Uri.encodeComponent(id)}',
      ) as Map;
      if (mounted) {
        setState(() {
          _result = r.cast<String, dynamic>();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorText(e);
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return AdminListScaffold(
      children: [
        Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _id,
                  decoration: InputDecoration(
                    labelText: tr('User, server, or channel ID'),
                    isDense: true,
                    border: const OutlineInputBorder(),
                    suffixIcon: _loading
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                  ),
                  onSubmitted: (_) => _lookup(),
                ),
              ),
              const SizedBox(width: Gap.sm),
              FilledButton(onPressed: _loading ? null : _lookup, child: Text(tr('Look up'))),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.md),
            child: Text(_error!, style: TextStyle(color: context.cs.error)),
          ),
        if (r != null)
          Card(
            margin: const EdgeInsets.all(Gap.md),
            child: Padding(
              padding: const EdgeInsets.all(Gap.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Chip(label: Text('${r['type']}')),
                      const SizedBox(width: Gap.sm),
                      Expanded(
                        child: SelectableText(
                          '${r['id']}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Gap.sm),
                  for (final kv in r.entries)
                    if (kv.key != 'type' && kv.key != 'id')
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 110,
                              child: Text(
                                kv.key,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text('${kv.value ?? '—'}'),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------- Platform Ban Records ----------------

class BanRecordsView extends StatefulWidget {
  const BanRecordsView({super.key});
  @override
  State<BanRecordsView> createState() => _BanRecordsViewState();
}

class _BanRecordsViewState extends State<BanRecordsView> {
  List<Map<String, dynamic>>? _bans;
  String? _error;
  bool _showLifted = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await context.read<ClientStore>().api.get('/admin/bans')
          as Map;
      if (mounted) {
        setState(() {
          _bans = (r['bans'] as List)
              .map((e) => (e as Map).cast<String, dynamic>())
              .toList();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _lift(Map<String, dynamic> b) async {
    var confirmed = false;
    await showAppDialog<void>(
      context,
      title: tr('Lift ban?'),
      content: Text(
        tr(
          'Lift the ban record for {user}? The account is only re-enabled if no other active bans remain.',
          {'user': '${b['user_id']}'},
        ),
      ),
      actions: [
        DlgAction(tr('Cancel')),
        DlgAction(
          tr('Lift ban'),
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
      await context.read<ClientStore>().api.post(
        '/admin/bans/${b['id']}/lift',
        {},
      );
      if (mounted) {
        showSnack(context, tr('Ban lifted.'));
        _load();
      }
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bans = _bans;
    if (bans == null || _error != null) {
      return _emptyOrError(_error, bans == null, tr('No ban records.'));
    }
    final shown = bans
        .where((b) => _showLifted || b['active'] == true)
        .toList();
    return AdminListScaffold(
      children: [
        Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  tr('{n} ban record(s)', {'n': bans.length}),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              FilterChip(
                label: Text(tr('Show lifted')),
                selected: _showLifted,
                onSelected: (v) => setState(() => _showLifted = v),
              ),
            ],
          ),
        ),
        for (final b in shown)
          ListTile(
            dense: true,
            leading: Icon(
              b['active'] == true ? Icons.block : Icons.check_circle_outline,
              size: 20,
              color: b['active'] == true ? context.cs.error : null,
            ),
            title: Text('${b['user_id']}'),
            subtitle: Text(
              [
                if ('${b['reason'] ?? ''}'.isNotEmpty) '${b['reason']}',
                'by ${b['issued_by']}',
                if (b['expires_at'] != null) 'expires ${b['expires_at']}',
                if (b['lifted_at'] != null) 'lifted ${b['lifted_at']}',
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: b['active'] == true
                ? IconButton(
                    icon: const Icon(Icons.undo, size: 20),
                    tooltip: tr('Lift ban'),
                    onPressed: () => _lift(b),
                  )
                : null,
          ),
        if (shown.isEmpty)
          _emptyOrError(null, false, tr('No ban records.')),
      ],
    );
  }
}

// ---------------- Content Moderation ----------------

class ContentModView extends StatefulWidget {
  const ContentModView({super.key});
  @override
  State<ContentModView> createState() => _ContentModViewState();
}

class _ContentModViewState extends State<ContentModView> {
  final _channel = TextEditingController();
  List<Map<String, dynamic>>? _messages;
  String? _channelName;
  bool _loading = false;
  String? _error;

  Future<void> _load() async {
    final id = _channel.text.trim();
    if (id.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _messages = null;
      _channelName = null;
    });
    final api = context.read<ClientStore>().api;
    try {
      final ch = await api.get('/channels/$id') as Map;
      final msgs = await api.get(
        '/channels/$id/messages',
        query: {'limit': '50'},
      ) as List;
      if (mounted) {
        setState(() {
          _channelName = ch['name'] as String? ?? id;
          _messages = msgs
              .map((e) => (e as Map).cast<String, dynamic>())
              .toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorText(e);
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final msgs = _messages;
    return AdminListScaffold(
      children: [
        Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _channel,
                  decoration: InputDecoration(
                    labelText: tr('Channel ID'),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _load(),
                ),
              ),
              const SizedBox(width: Gap.sm),
              FilledButton(
                onPressed: _loading ? null : _load,
                child: Text(tr('Inspect')),
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.md),
            child: Text(_error!, style: TextStyle(color: context.cs.error)),
          ),
        if (_channelName != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.md),
            child: Text(
              tr('Channel: {name}', {'name': _channelName!}),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        if (msgs != null)
          for (final m in msgs.reversed)
            ListTile(
              dense: true,
              leading: const Icon(Icons.chat_bubble_outline, size: 20),
              title: Text('${m['author']}'),
              subtitle: Text(
                '${m['content'] ?? ''}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(
                (m['id'] as String? ?? '').substring(
                  0,
                  ((m['id'] as String? ?? '').length).clamp(0, 8),
                ),
                style: const TextStyle(fontSize: 11),
              ),
            ),
        if (msgs != null && msgs.isEmpty)
          _emptyOrError(null, false, tr('No messages in this channel.')),
      ],
    );
  }
}

// ---------------- Diagnostics ----------------

class DiagnosticsView extends StatefulWidget {
  const DiagnosticsView({super.key});
  @override
  State<DiagnosticsView> createState() => _DiagnosticsViewState();
}

class _DiagnosticsViewState extends State<DiagnosticsView> {
  final _results = <String, (String, int?)>{};
  bool _running = false;

  Future<void> _check(String name, String url) async {
    final sw = Stopwatch()..start();
    try {
      final res = await sendRequest('GET', url)
          .timeout(const Duration(seconds: 8));
      sw.stop();
      _results[name] = ('HTTP ${res.status}', sw.elapsedMilliseconds);
    } catch (e) {
      sw.stop();
      _results[name] = ('${e.runtimeType}', sw.elapsedMilliseconds);
    }
  }

  Future<void> _run() async {
    setState(() => _running = true);
    _results.clear();
    final api = context.read<ClientStore>().api;
    final ws = api.config?.ws ?? '';
    final targets = <String, String>{
      'API': '${api.baseUrl}/',
      if (ws.isNotEmpty) 'WebSocket': ws,
      if (api.config?.autumnUrl.isNotEmpty ?? false)
        'Autumn': '${api.config!.autumnUrl}/',
    };
    await Future.wait([for (final e in targets.entries) _check(e.key, e.value)]);
    if (mounted) setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    return AdminListScaffold(
      children: [
        Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('Check connectivity to platform services.'),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: Gap.md),
              FilledButton.icon(
                onPressed: _running ? null : _run,
                icon: _running
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.network_check, size: 18),
                label: Text(tr('Run diagnostics')),
              ),
              const SizedBox(height: Gap.md),
              for (final e in _results.entries)
                ListTile(
                  dense: true,
                  leading: Icon(
                    e.value.$1.startsWith('HTTP 2')
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    size: 20,
                    color: e.value.$1.startsWith('HTTP 2')
                        ? Colors.green
                        : context.cs.error,
                  ),
                  title: Text(e.key),
                  subtitle: Text(e.value.$1),
                  trailing: Text('${e.value.$2 ?? 0}ms'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------- Name & Identity History ----------------

class HistoryView extends StatefulWidget {
  const HistoryView({super.key});
  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  final _type = TextEditingController();
  final _id = TextEditingController();
  List<Map<String, dynamic>>? _entries;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final q = <String, dynamic>{'limit': '300'};
      if (_type.text.trim().isNotEmpty) q['entity_type'] = _type.text.trim();
      if (_id.text.trim().isNotEmpty) q['entity_id'] = _id.text.trim();
      final r = await context.read<ClientStore>().api.get(
        '/admin/history',
        query: q,
      ) as Map;
      if (mounted) {
        setState(() {
          _entries = (r['entries'] as List)
              .map((e) => (e as Map).cast<String, dynamic>())
              .toList();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    if (entries == null || _error != null) {
      return _emptyOrError(_error, entries == null, tr('No history entries.'));
    }
    return AdminListScaffold(
      children: [
        Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Row(
            children: [
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _type,
                  decoration: InputDecoration(
                    labelText: tr('Type'),
                    hintText: 'user/server/role',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: TextField(
                  controller: _id,
                  decoration: InputDecoration(
                    labelText: tr('Entity ID'),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _load(),
                ),
              ),
              const SizedBox(width: Gap.sm),
              FilledButton(onPressed: _load, child: Text(tr('Filter'))),
            ],
          ),
        ),
        for (final e in entries)
          ListTile(
            dense: true,
            leading: Icon(
              switch (e['entity_type']) {
                'user' => Icons.person_outline,
                'server' => Icons.dns_outlined,
                'role' => Icons.badge_outlined,
                _ => Icons.edit_outlined,
              },
              size: 20,
            ),
            title: Text(
              '${e['entity_label'] ?? e['entity_id']} — ${e['field']}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${e['old_value'] ?? '—'} → ${e['new_value'] ?? '—'}\n'
              'by ${e['actor_id']} · ${e['entity_type']}:${e['entity_id']}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            isThreeLine: true,
            trailing: Text(
              (e['created_at'] as String? ?? '').split('T').first,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        if (entries.isEmpty)
          _emptyOrError(null, false, tr('No history entries.')),
      ],
    );
  }
}
