import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../api/client_store.dart';
import '../../../core/i18n.dart';
import '../../../theme/tokens.dart';
import '../../modals/app_dialog.dart';
import '../../net_image.dart';
import '../../widgets.dart';
import '../admin_base.dart';

/// User directory with search, filters and a full detail editor.
/// [staffOnly] restricts the list to users with admin access;
/// [focusUserId] opens that user's detail automatically (deep links).
class UsersView extends StatefulWidget {
  const UsersView({
    super.key,
    this.staffOnly = false,
    this.deletedOnly = false,
    this.disabledOnly = false,
    this.focusUserId,
  });
  final bool staffOnly;
  final bool deletedOnly;
  final bool disabledOnly;
  final String? focusUserId;

  @override
  State<UsersView> createState() => UsersViewState();
}

class UsersViewState extends State<UsersView> {
  final _search = TextEditingController();
  bool _bannedOnly = false;
  bool _staffOnly = false;
  bool _deletedOnly = false;
  bool _disabledOnly = false;
  bool _botsOnly = false;
  List<Map<String, dynamic>>? _users;
  String? _error;
  String? _focused;

  @override
  void initState() {
    super.initState();
    _staffOnly = widget.staffOnly;
    _deletedOnly = widget.deletedOnly;
    _disabledOnly = widget.disabledOnly;
    _focused = widget.focusUserId;
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
          if (_staffOnly) 'staff': 'true',
          'deleted': _deletedOnly ? 'true' : 'false',
          if (!widget.deletedOnly)
            'disabled': _disabledOnly ? 'true' : 'false',
          if (_botsOnly) 'bot': 'true',
          'limit': '200',
        },
      ) as List;
      if (mounted) {
        setState(() {
          _users = r.map((e) => (e as Map).cast<String, dynamic>()).toList();
          _error = null;
        });
        if (_focused != null) {
          final id = _focused!;
          _focused = null;
          final match = _users!.where((u) => '${u['_id']}' == id);
          if (match.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => openUser(match.first),
            );
          } else {
            // Not in the current filtered page — fetch directly.
            _openById(id);
          }
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _openById(String id) async {
    try {
      final u = await context.read<ClientStore>().api.get(
        '/admin/users/$id',
      ) as Map;
      if (mounted) openUser(u.cast<String, dynamic>());
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    }
  }

  static bool isBanned(Map<String, dynamic> u) =>
      ((u['flags'] as num?)?.toInt() ?? 0) & 4 != 0;
  static bool isDisabled(Map<String, dynamic> u) {
    final f = (u['flags'] as num?)?.toInt() ?? 0;
    return f & 1 != 0 || u['disabled'] == true || u['suspended_until'] != null;
  }

  Future<void> openUser(Map<String, dynamic> u) async {
    final store = context.read<ClientStore>();
    final canEdit = store.canAdmin(ClientStore.adminEditUsers);
    final canBan = store.canAdmin(ClientStore.adminBanUsers);
    final isPrivilegedActor = store.me?['privileged'] == true;

    var displayName = u['display_name'] as String? ?? '';
    var badges = (u['badges'] as num?)?.toInt() ?? 0;
    var privileged = u['privileged'] == true;
    var perms = (u['admin_permissions'] as num?)?.toInt() ?? 0;
    final banned = isBanned(u);

    // Only full admins may grant privileged/admin access (matches backend).
    final canGrantAccess = canEdit && isPrivilegedActor;

    await showAppDialog<void>(
      context,
      title: '${u['username']}#${u['discriminator']}',
      maxWidth: 640,
      content: StatefulBuilder(
        builder: (context, setDlg) => SizedBox(
          width: 560,
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
                  decoration: InputDecoration(labelText: tr('Display Name')),
                  maxLength: 200,
                  onChanged: (v) => displayName = v,
                  controller: TextEditingController(text: displayName)
                    ..selection = TextSelection.collapsed(
                      offset: displayName.length,
                    ),
                ),
                const SizedBox(height: 8),
                Text(
                  tr('Badges'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                AdminBadgeEditor(
                  value: badges,
                  enabled: canEdit,
                  onChanged: (v) => setDlg(() => badges = v),
                ),
                const SizedBox(height: 8),
                Text(
                  tr('Admin access'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                AdminToggleList(
                  children: [
                    AdminToggleRow(
                      label: 'Privileged',
                      description:
                          'Full admin access — bypasses every permission check',
                      enabled: canGrantAccess,
                      value: privileged,
                      onChanged: (v) => setDlg(() => privileged = v),
                    ),
                  ],
                ),
                AdminPermEditor(
                  value: perms,
                  enabled: canGrantAccess,
                  onChanged: (v) => setDlg(() => perms = v),
                ),
              ] else ...[
                Text('${u['display_name'] ?? ''}'),
                Text(
                  'Badges: ${u['badges'] ?? 0} · Admin perms: ${u['admin_permissions'] ?? 0}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
              if (isDisabled(u) || banned || u['disabled'] == true)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    banned
                        ? tr('BANNED')
                        : u['disabled'] == true
                        ? tr('Account disabled')
                        : tr('Account suspended'),
                    style: TextStyle(color: context.cs.error),
                  ),
                ),
              UserStanding(userId: '${u['_id']}'),
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
                  'display_name': displayName,
                  'badges': badges,
                  if (canGrantAccess) 'privileged': privileged,
                  if (canGrantAccess) 'admin_permissions': perms,
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
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final users = _users;
    final canEdit = store.canAdmin(ClientStore.adminEditUsers);
    final canBan = store.canAdmin(ClientStore.adminBanUsers);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminPageHeader(
          title: widget.staffOnly
              ? 'Staff'
              : widget.deletedOnly
              ? 'Deleted Accounts'
              : widget.disabledOnly
              ? 'Disabled Accounts'
              : 'User Directory',
          subtitle: widget.staffOnly
              ? 'Manage administrator permissions'
              : widget.deletedOnly
              ? 'Deleted users and bots'
              : widget.disabledOnly
              ? 'Suspended or disabled accounts'
              : 'Search and manage platform users',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.md),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    hintText: tr(
                      'Search, or filters: deleted: -disabled banned: staff: bot:',
                    ),
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _load(),
                ),
              ),
              FilterChip(
                label: Text(tr('Banned')),
                selected: _bannedOnly,
                onSelected: (v) {
                  setState(() => _bannedOnly = v);
                  _load();
                },
              ),
              FilterChip(
                label: Text(tr('Staff')),
                selected: _staffOnly,
                onSelected: (v) {
                  setState(() => _staffOnly = v);
                  _load();
                },
              ),
              FilterChip(
                label: Text(tr('Deleted')),
                selected: _deletedOnly,
                onSelected: widget.deletedOnly
                    ? null
                    : (v) {
                        setState(() => _deletedOnly = v);
                        _load();
                      },
              ),
              FilterChip(
                label: Text(tr('Disabled')),
                selected: _disabledOnly,
                onSelected: widget.disabledOnly || widget.deletedOnly
                    ? null
                    : (v) {
                        setState(() => _disabledOnly = v);
                        _load();
                      },
              ),
              FilterChip(
                label: Text(tr('Bots')),
                selected: _botsOnly,
                onSelected: (v) {
                  setState(() => _botsOnly = v);
                  _load();
                },
              ),
              FilledButton.tonal(
                onPressed: _load,
                child: Text(tr('Search')),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.sm),
        Expanded(
          child: _error != null
              ? adminEmptyOrError(_error, false, '')
              : users == null
              ? const Center(child: CircularProgressIndicator())
              : users.isEmpty
              ? adminEmptyOrError(null, false, tr('No users found.'))
              : AdminListScaffold(
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
                          '${isBanned(u) ? ' • ${tr('BANNED')}' : ''}'
                          '${isDisabled(u) ? ' • ${tr('Suspended')}' : ''}'
                          '${u['privileged'] == true ? ' • ⭐' : ''}'
                          '${(u['admin_permissions'] as num? ?? 0) > 0 ? ' • ${tr('Staff')}' : ''}',
                        ),
                        action: canEdit || canBan
                            ? const Icon(Icons.chevron_right)
                            : null,
                        onTap: () => openUser(u),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Moderation standing panel — ban records, suspension state, strikes,
/// with suspend/unsuspend actions.
class UserStanding extends StatefulWidget {
  const UserStanding({super.key, required this.userId});
  final String userId;

  @override
  State<UserStanding> createState() => _UserStandingState();
}

class _UserStandingState extends State<UserStanding> {
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
