import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/client_store.dart';
import '../../core/i18n.dart';
import '../../router.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../modals/app_dialog.dart';
import '../net_image.dart';
import '../settings/settings_page.dart';
import '../widgets.dart';
import 'admin_sections.dart';
import 'changelog_admin.dart';

/// Platform admin panel — ported from DawnAdmin. Sections are gated by the
/// caller's admin permission bitfield (or `privileged` for full access).
class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  String _section = 'users';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final cs = context.cs;
    final phone =
        screenClassOf(MediaQuery.sizeOf(context)) == ScreenClass.phone;

    final sections = <(String, String, IconData, bool)>[
      (
        'overview',
        tr('Overview'),
        Icons.dashboard_outlined,
        store.canAdmin(ClientStore.adminViewAudit),
      ),
      (
        'users',
        tr('Users'),
        Icons.people_outline,
        store.canAdmin(ClientStore.adminViewUsers),
      ),
      (
        'reports',
        tr('Reports'),
        Icons.flag_outlined,
        store.canAdmin(ClientStore.adminViewReports),
      ),
      (
        'bans',
        tr('Bans'),
        Icons.gavel_outlined,
        store.canAdmin(ClientStore.adminViewUsers) &&
            store.canAdmin(ClientStore.adminBanUsers),
      ),
      (
        'ban_records',
        tr('Ban Records'),
        Icons.list_alt_outlined,
        store.canAdmin(ClientStore.adminBanUsers),
      ),
      (
        'lookup',
        tr('Lookup'),
        Icons.search_outlined,
        store.canAdmin(ClientStore.adminViewUsers),
      ),
      (
        'content',
        tr('Content'),
        Icons.forum_outlined,
        store.canAdmin(ClientStore.adminViewReports) ||
            store.canAdmin(ClientStore.adminManageReports),
      ),
      (
        'diagnostics',
        tr('Diagnostics'),
        Icons.monitor_heart_outlined,
        store.canAdmin(ClientStore.adminViewAudit),
      ),
      (
        'history',
        tr('History'),
        Icons.manage_history_outlined,
        store.canAdmin(ClientStore.adminViewAudit),
      ),
      (
        'changelogs',
        tr('Changelogs'),
        Icons.campaign_outlined,
        store.canAdmin(ClientStore.adminBroadcast),
      ),
      (
        'audit',
        tr('Audit Log'),
        Icons.history,
        store.canAdmin(ClientStore.adminViewAudit),
      ),
      (
        'strikes',
        tr('Strikes'),
        Icons.gavel_outlined,
        store.canAdmin(ClientStore.adminViewReports) ||
            store.canAdmin(ClientStore.adminManageReports),
      ),
      (
        'servers',
        tr('Servers'),
        Icons.dns_outlined,
        store.canAdmin(ClientStore.adminViewServers) ||
            store.canAdmin(ClientStore.adminEditServers),
      ),
      (
        'bots',
        tr('Bots'),
        Icons.smart_toy_outlined,
        store.canAdmin(ClientStore.adminViewUsers) ||
            store.canAdmin(ClientStore.adminEditUsers),
      ),
      (
        'announce',
        tr('Announce'),
        Icons.campaign,
        store.canAdmin(ClientStore.adminBroadcast),
      ),
    ];
    final visible = sections.where((s) => s.$4).toList();
    if (visible.isEmpty) {
      return Scaffold(
        body: Center(
          child: Text(
            tr('You do not have permission to access the admin panel.'),
          ),
        ),
      );
    }
    if (!visible.any((s) => s.$1 == _section)) {
      _section = visible.first.$1;
    }

    final nav = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in visible)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: SettingsNavRow(
              icon: s.$3,
              title: tr(s.$2),
              selected: _section == s.$1,
              onTap: () => setState(() => _section = s.$1),
            ),
          ),
      ],
    );

    final body = switch (_section) {
      'overview' => const OverviewView(),
      'reports' => const _ReportsView(),
      'bans' => const _BansView(),
      'ban_records' => const BanRecordsView(),
      'lookup' => const LookupView(),
      'content' => const ContentModView(),
      'diagnostics' => const DiagnosticsView(),
      'history' => const HistoryView(),
      'changelogs' => const ChangelogsView(),
      'audit' => const AuditView(),
      'strikes' => const StrikesView(),
      'servers' => const ServersView(),
      'bots' => const BotsView(),
      'announce' => const AnnounceView(),
      _ => const _UsersView(),
    };

    if (phone) {
      return Scaffold(
        appBar: AppBar(
          title: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _section,
              isDense: true,
              items: [
                for (final s in visible)
                  DropdownMenuItem(value: s.$1, child: Text(tr(s.$2))),
              ],
              onChanged: (v) => setState(() => _section = v ?? _section),
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.goPath('/app'),
          ),
        ),
        body: SafeArea(child: body),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 240,
            child: ListView(
              padding: const EdgeInsets.all(Gap.md),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: Gap.md),
                  child: Row(
                    children: [
                      Icon(
                        Icons.admin_panel_settings_outlined,
                        color: cs.primary,
                      ),
                      const SizedBox(width: Gap.sm),
                      Text(
                        tr('Admin'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                nav,
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Container(
              color: cs.surface,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Gap.xl),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: body,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UsersView extends StatefulWidget {
  const _UsersView();

  @override
  State<_UsersView> createState() => _UsersViewState();
}

class _UsersViewState extends State<_UsersView> {
  final _search = TextEditingController();
  bool _bannedOnly = false;
  List<Map<String, dynamic>>? _users;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await context.read<ClientStore>().api.get(
        '/admin/users',
        query: {
          if (_search.text.trim().isNotEmpty) 'q': _search.text.trim(),
          if (_bannedOnly) 'banned': 'true',
          'limit': '100',
        },
      ) as List;
      if (mounted) {
        setState(() {
          _users = r.map((e) => (e as Map).cast<String, dynamic>()).toList();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  bool _flag(Map<String, dynamic> u, int bit) =>
      ((u['flags'] as num?)?.toInt() ?? 0) & bit != 0;
  bool _isBanned(Map<String, dynamic> u) => _flag(u, 4);
  bool _isDisabled(Map<String, dynamic> u) => _flag(u, 1) || _flag(u, 2);

  Future<void> _openUser(Map<String, dynamic> u) async {
    final store = context.read<ClientStore>();
    final canEdit = store.canAdmin(ClientStore.adminEditUsers);
    final canBan = store.canAdmin(ClientStore.adminBanUsers);
    final name = TextEditingController(
      text: u['display_name'] as String? ?? '',
    );
    final badges = TextEditingController(
      text: '${(u['badges'] as num?)?.toInt() ?? 0}',
    );
    var privileged = u['privileged'] == true;
    final perms = (u['admin_permissions'] as num?)?.toInt() ?? 0;
    final permsCtl = TextEditingController(text: '$perms');
    final banned = _isBanned(u);

    await showAppDialog<void>(
      context,
      title: '${u['username']}#${u['discriminator']}',
      content: StatefulBuilder(
        builder: (context, setDlg) => SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ID: ${u['_id']}',
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: context.cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              if (canEdit) ...[
                TextField(
                  controller: name,
                  maxLength: 200,
                  decoration: InputDecoration(labelText: tr('Display Name')),
                ),
                TextField(
                  controller: badges,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: tr('Badges (bitfield)'),
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Privileged'),
                  value: privileged,
                  onChanged: (v) => setDlg(() => privileged = v ?? false),
                ),
                TextField(
                  controller: permsCtl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: tr('Admin permissions (bitfield)'),
                    helperText: tr(
                      'ViewUsers=1 EditUsers=2 BanUsers=4 ViewReports=8 '
                      'ManageReports=16 ViewAudit=32 ViewServers=64 '
                      'EditServers=128 Broadcast=256',
                    ),
                  ),
                  onChanged: (v) {},
                ),
              ] else ...[
                Text('${u['display_name'] ?? ''}'),
              ],
              if (_isDisabled(u) || banned || u['disabled'] == true)
                Text(
                  banned
                      ? tr('BANNED')
                      : u['disabled'] == true
                      ? tr('Account disabled')
                      : tr('Account suspended'),
                  style: TextStyle(color: context.cs.error),
                ),
              const SizedBox(height: 12),
              _UserStanding(userId: '${u['_id']}'),
            ],
          ),
        ),
      ),
      actions: [
        DlgAction(tr('Close')),
        if (canBan)
          DlgAction(
            banned ? tr('Unban') : tr('Ban'),
            onPressed: () async {
              try {
                if (banned) {
                  await store.api.delete('/admin/users/${u['_id']}/ban');
                } else {
                  final reason = await promptText(
                    context,
                    tr('Ban user'),
                    label: tr('Reason'),
                    action: tr('Ban'),
                  );
                  if (reason == null) return false;
                  await store.api.post('/admin/users/${u['_id']}/ban', {
                    'reason': reason,
                  });
                }
                await _load();
                return null;
              } catch (e) {
                if (context.mounted) showSnack(context, errorText(e));
                return false;
              }
            },
          ),
        if (canEdit)
          DlgAction(
            tr('Save'),
            onPressed: () async {
              try {
                await store.api.patch('/admin/users/${u['_id']}', {
                  'display_name': name.text,
                  'badges': int.tryParse(badges.text) ?? 0,
                  'privileged': privileged,
                  'admin_permissions': int.tryParse(permsCtl.text) ?? perms,
                });
                await _load();
                return null;
              } catch (e) {
                if (context.mounted) showSnack(context, errorText(e));
                return false;
              }
            },
          ),
      ],
    );
    name.dispose();
    badges.dispose();
    permsCtl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final users = _users;
    final canEdit = store.canAdmin(ClientStore.adminEditUsers);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('User Directory'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 280,
              child: TextField(
                controller: _search,
                decoration: InputDecoration(
                  hintText: tr('Search username, display name or ID'),
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                ),
                onSubmitted: (_) => _load(),
              ),
            ),
            FilterChip(
              label: Text(tr('Banned only')),
              selected: _bannedOnly,
              onSelected: (v) {
                setState(() => _bannedOnly = v);
                _load();
              },
            ),
            FilledButton.tonal(onPressed: _load, child: Text(tr('Search'))),
          ],
        ),
        const SizedBox(height: 16),
        if (_error != null)
          Text(_error!, style: TextStyle(color: context.cs.error))
        else if (users == null)
          const Center(child: CircularProgressIndicator())
        else if (users.isEmpty)
          Text(
            tr('No users found.'),
            style: TextStyle(color: context.cs.onSurfaceVariant),
          )
        else
          CategoryGroup(
            children: [
              for (final u in users)
                CategoryButton(
                  icon: NetImage(
                    store.api.fileUrl(
                          'avatars',
                          u['avatar'] as Map?,
                          width: 96,
                        ) ??
                        '',
                    width: 24,
                    height: 24,
                  ),
                  title: Text('${u['username']}#${u['discriminator']}'),
                  description: Text(
                    '${u['display_name'] ?? ''}'
                    '${_isBanned(u) ? ' • ${tr('BANNED')}' : ''}'
                    '${_isDisabled(u) ? ' • ${tr('Suspended')}' : ''}',
                  ),
                  action: canEdit || store.canAdmin(ClientStore.adminBanUsers)
                      ? const Icon(Icons.chevron_right)
                      : null,
                  onTap: () => _openUser(u),
                ),
            ],
          ),
      ],
    );
  }
}

class _ReportsView extends StatefulWidget {
  const _ReportsView();

  @override
  State<_ReportsView> createState() => _ReportsViewState();
}

class _ReportsViewState extends State<_ReportsView> {
  List<Map<String, dynamic>>? _reports;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await context.read<ClientStore>().api.get(
        '/admin/reports',
        query: {'limit': '200'},
      ) as List;
      if (mounted) {
        setState(() {
          _reports = r.map((e) => (e as Map).cast<String, dynamic>()).toList();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _act(Map<String, dynamic> r, String action) async {
    final store = context.read<ClientStore>();
    String? reason;
    if (action == 'reject') {
      reason = await promptText(
        context,
        tr('Reject report'),
        label: tr('Rejection reason'),
        action: tr('Reject'),
      );
      if (reason == null || !mounted) return;
    }
    try {
      await store.api.patch('/admin/reports/${r['id']}', {
        'action': action,
        if (reason != null) 'rejection_reason': reason,
      });
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final canManage = store.canAdmin(ClientStore.adminManageReports);
    final reports = _reports;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('Safety Reports'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        if (_error != null)
          Text(_error!, style: TextStyle(color: context.cs.error))
        else if (reports == null)
          const Center(child: CircularProgressIndicator())
        else if (reports.isEmpty)
          Text(
            tr('No reports.'),
            style: TextStyle(color: context.cs.onSurfaceVariant),
          )
        else
          CategoryGroup(
            children: [
              for (final r in reports)
                CategoryButton(
                  icon: Icon(
                    r['status'] == 'Created' ? Icons.flag : Icons.flag_outlined,
                  ),
                  title: Text('${r['status']} — ${r['author_id']}'),
                  description: Text(
                    '${r['additional_context'] ?? ''}'
                    '${r['content'] != null ? ' • ${r['content']}' : ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  action: canManage && r['status'] == 'Created'
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: tr('Resolve'),
                              icon: const Icon(Icons.check),
                              onPressed: () => _act(r, 'resolve'),
                            ),
                            IconButton(
                              tooltip: tr('Reject'),
                              icon: const Icon(Icons.close),
                              onPressed: () => _act(r, 'reject'),
                            ),
                          ],
                        )
                      : null,
                ),
            ],
          ),
      ],
    );
  }
}

class _BansView extends StatefulWidget {
  const _BansView();

  @override
  State<_BansView> createState() => _BansViewState();
}

class _BansViewState extends State<_BansView> {
  List<Map<String, dynamic>>? _users;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await context.read<ClientStore>().api.get(
        '/admin/users',
        query: {'banned': 'true', 'limit': '200'},
      ) as List;
      if (mounted) {
        setState(() {
          _users = r.map((e) => (e as Map).cast<String, dynamic>()).toList();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final users = _users;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('Platform Bans'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        if (_error != null)
          Text(_error!, style: TextStyle(color: context.cs.error))
        else if (users == null)
          const Center(child: CircularProgressIndicator())
        else if (users.isEmpty)
          Text(
            tr('No banned users.'),
            style: TextStyle(color: context.cs.onSurfaceVariant),
          )
        else
          CategoryGroup(
            children: [
              for (final u in users)
                CategoryButton(
                  icon: const Icon(Icons.gavel_outlined),
                  title: Text('${u['username']}#${u['discriminator']}'),
                  description: Text(u['display_name'] as String? ?? ''),
                  action: IconButton(
                    tooltip: tr('Unban'),
                    icon: const Icon(Icons.lock_open_outlined),
                    onPressed: () async {
                      try {
                        await store.api.delete('/admin/users/${u['_id']}/ban');
                        await _load();
                      } catch (e) {
                        if (context.mounted) {
                          showSnack(context, errorText(e));
                        }
                      }
                    },
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// Moderation standing panel inside the user detail dialog — shows ban
/// records (reason + expiry), suspension state and strike count, with
/// suspend/unsuspend actions.
class _UserStanding extends StatefulWidget {
  const _UserStanding({required this.userId});
  final String userId;

  @override
  State<_UserStanding> createState() => _UserStandingState();
}

class _UserStandingState extends State<_UserStanding> {
  Map<String, dynamic>? _standing;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await context.read<ClientStore>().api.get(
        '/admin/users/${widget.userId}/standing',
      ) as Map;
      if (mounted) {
        setState(() {
          _standing = r.cast<String, dynamic>();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _restrict(String action) async {
    int? durationSecs;
    String reason = '';
    if (action == 'suspend') {
      final dur = await promptText(
        context,
        tr('Suspend account'),
        label: tr('Duration in hours (empty = indefinite)'),
      );
      if (dur == null || !mounted) return;
      final h = int.tryParse(dur.trim());
      if (dur.trim().isNotEmpty && (h == null || h <= 0)) {
        showSnack(context, tr('Invalid duration.'));
        return;
      }
      durationSecs = h == null ? null : h * 3600;
      final r = await promptText(context, tr('Reason'), label: tr('Reason'));
      if (r == null) return;
      reason = r.trim();
    }
    try {
      await context.read<ClientStore>().api.post(
        '/admin/users/${widget.userId}/restrict',
        {
          'action': action,
          'duration_secs': ?durationSecs,
          'reason': reason,
        },
      );
      _load();
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final s = _standing;
    if (_error != null) {
      return Text(_error!, style: TextStyle(color: cs.error, fontSize: 12));
    }
    if (s == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      );
    }
    final bans = (s['bans'] as List?) ?? const [];
    final banned = s['banned'] == true;
    final disabled = s['disabled'] == true;
    final suspendedUntil = s['suspended_until'] as String?;
    final strikes = (s['strike_count'] as num?)?.toInt() ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 16),
        Text(
          tr('Moderation standing'),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
        const SizedBox(height: 6),
        Text(
          'Strikes: $strikes'
          '${disabled ? ' · ${tr('Disabled')}' : ''}'
          '${suspendedUntil != null ? ' · ${tr('Suspended until')} ${suspendedUntil.split('T').first}' : ''}',
          style: const TextStyle(fontSize: 12),
        ),
        if (bans.isNotEmpty) ...[
          const SizedBox(height: 6),
          for (final b in bans.take(5))
            Text(
              '• ${b['active'] == true ? tr('Active ban') : tr('Ban lifted')} — ${b['reason'] ?? ''}'
              '${b['expires_at'] != null ? ' · ${tr('expires')} ${(b['expires_at'] as String).split('T').first}' : ' · ${tr('permanent')}'}',
              style: const TextStyle(fontSize: 12),
            ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            if (!banned)
              OutlinedButton.icon(
                icon: const Icon(Icons.pause_circle_outline, size: 16),
                label: Text(tr('Suspend')),
                onPressed: () => _restrict('suspend'),
              ),
            if (disabled && !banned)
              OutlinedButton.icon(
                icon: const Icon(Icons.play_circle_outline, size: 16),
                label: Text(tr('Unsuspend')),
                onPressed: () => _restrict('unsuspend'),
              ),
          ],
        ),
      ],
    );
  }
}
