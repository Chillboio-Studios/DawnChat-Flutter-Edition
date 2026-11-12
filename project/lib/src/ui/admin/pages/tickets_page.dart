import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../api/client_store.dart';
import '../../../core/i18n.dart';
import '../../../theme/tokens.dart';
import '../../modals/app_dialog.dart';
import '../../widgets.dart';
import '../admin_base.dart';

/// Support ticket queue — staff investigate reports and user issues
/// through threaded tickets.
class TicketsView extends StatefulWidget {
  const TicketsView({super.key, this.focusTicketId});
  final String? focusTicketId;

  @override
  State<TicketsView> createState() => TicketsViewState();
}

class TicketsViewState extends State<TicketsView> {
  String _status = '';
  List<Map<String, dynamic>>? _tickets;
  String? _error;
  String? _focused;

  @override
  void initState() {
    super.initState();
    _focused = widget.focusTicketId;
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await context.read<ClientStore>().api.get(
        '/admin/tickets',
        query: {
          'limit': '200',
          if (_status.isNotEmpty) 'status': _status,
        },
      ) as List;
      if (mounted) {
        setState(() {
          _tickets = r.map((e) => (e as Map).cast<String, dynamic>()).toList();
          _error = null;
        });
        if (_focused != null) {
          final id = _focused!;
          _focused = null;
          final match = _tickets!.where((t) => '${t['_id']}' == id);
          if (match.isNotEmpty) {
            openTicket(match.first);
          } else {
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
      final t = await context.read<ClientStore>().api.get(
        '/admin/tickets/$id',
      ) as Map;
      if (mounted) openTicket(t.cast<String, dynamic>());
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    }
  }

  Future<void> _patch(String id, Map<String, dynamic> body) async {
    try {
      await context.read<ClientStore>().api.patch('/admin/tickets/$id', body);
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    }
  }

  Future<void> openTicket(Map<String, dynamic> t) async {
    final store = context.read<ClientStore>();
    final canManage = store.canAdmin(ClientStore.adminManageReports);
    final canModerate = store.canAdmin(ClientStore.adminEditUsers);
    // Refresh full ticket (with messages) before showing.
    Map<String, dynamic> full;
    try {
      full = (await store.api.get('/admin/tickets/${t['_id']}') as Map)
          .cast<String, dynamic>();
    } catch (_) {
      full = t;
    }
    if (!mounted) return;

    var status = '${full['status']}';
    var priority = '${full['priority'] ?? 'normal'}';
    final subject = TextEditingController(text: '${full['subject']}');
    final notes = TextEditingController(text: '${full['staff_notes'] ?? ''}');
    final reply = TextEditingController();
    final messages = (full['messages'] as List? ?? const [])
        .map((m) => (m as Map).cast<String, dynamic>())
        .toList();

    // Resolve the linked report to identify the reporter + reported content.
    Map<String, dynamic>? report;
    if (full['report_id'] != null) {
      try {
        final reports = await store.api.get(
          '/admin/reports',
          query: {'limit': '500'},
        ) as List;
        for (final r in reports) {
          final rm = (r as Map).cast<String, dynamic>();
          if ('${rm['_id']}' == '${full['report_id']}') {
            report = rm;
            break;
          }
        }
      } catch (_) {}
    }
    if (!mounted) return;
    final reporterId = report?['author_id'] as String?;
    final reporteeId = switch (report?['content']) {
      {'type': 'User', 'id': final String id} => id,
      _ => '${full['user_id']}',
    };

    await showAppDialog<void>(
      context,
      title: 'Ticket ${full['_id']}',
      maxWidth: 680,
      content: StatefulBuilder(
        builder: (context, setDlg) => SizedBox(
          width: 620,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _chip(context, 'User: ${full['user_id']}'),
                  if (full['report_id'] != null)
                    _chip(context, 'Report: ${full['report_id']}'),
                  _chip(context, 'By: ${full['created_by']}'),
                  _chip(
                    context,
                    '${(full['created_at'] as String? ?? '').split('T').first}',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Thread
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final m in messages)
                      Align(
                        alignment: m['is_staff'] == true
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: m['is_staff'] == true
                                ? context.cs.secondaryContainer
                                : context.cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${m['author_id']}${m['is_staff'] == true ? ' • ${tr('Staff')}' : ''}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: context.cs.onSurfaceVariant,
                                ),
                              ),
                              Text('${m['body']}'),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (canManage || canModerate) ...[
                const Divider(height: 20),
                _label(context, 'Involved users'),
                const SizedBox(height: 6),
                for (final entry in _involvedUsers(full, reporteeId, reporterId))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '${entry.$2} • ${entry.$1}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        if (canModerate)
                          ActionChip(
                            avatar: const Icon(Icons.pause_circle_outline, size: 16),
                            label: const Text('Suspend'),
                            onPressed: () => _moderateUser(
                              context,
                              store,
                              entry.$1,
                              suspend: true,
                            ),
                          ),
                        if (canModerate)
                          ActionChip(
                            avatar: const Icon(Icons.shield_outlined, size: 16),
                            label: const Text('Ban'),
                            onPressed: () => _moderateUser(
                              context,
                              store,
                              entry.$1,
                              suspend: false,
                            ),
                          ),
                        if (canModerate)
                          ActionChip(
                            avatar: const Icon(Icons.undo, size: 16),
                            label: const Text('Lift'),
                            onPressed: () => _liftModeration(
                              context,
                              store,
                              entry.$1,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
              if (canManage) ...[
                const Divider(height: 20),
                TextField(
                  controller: reply,
                  maxLines: 2,
                  maxLength: 10000,
                  decoration: InputDecoration(
                    labelText: tr('Reply as staff'),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: subject,
                  maxLength: 200,
                  decoration: InputDecoration(labelText: tr('Subject')),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: notes,
                  maxLines: 2,
                  maxLength: 5000,
                  decoration: InputDecoration(
                    labelText: tr('Internal staff notes'),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _label(context, 'Status'),
                    for (final s in [
                      'open',
                      'in_progress',
                      'resolved',
                      'closed',
                    ])
                      ChoiceChip(
                        label: Text(s.replaceAll('_', ' ')),
                        selected: status == s,
                        onSelected: (_) => setDlg(() => status = s),
                      ),
                    _label(context, 'Priority'),
                    for (final p in ['low', 'normal', 'high', 'urgent'])
                      ChoiceChip(
                        label: Text(p),
                        selected: priority == p,
                        onSelected: (_) => setDlg(() => priority = p),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        DlgAction(tr('Close')),
        if (canManage)
          DlgAction(
            tr('Save'),
            onPressed: () async {
              await _patch('${full['_id']}', {
                'status': status,
                'priority': priority,
                'subject': subject.text,
                'staff_notes': notes.text,
                if (reply.text.trim().isNotEmpty) 'message': reply.text.trim(),
              });
              return null;
            },
          ),
      ],
    );
    subject.dispose();
    notes.dispose();
    reply.dispose();
  }

  /// Unique (userId, role) pairs involved in this ticket.
  List<(String, String)> _involvedUsers(
    Map<String, dynamic> t,
    String reporteeId,
    String? reporterId,
  ) {
    final seen = <String>{};
    final out = <(String, String)>[];
    void add(String id, String role) {
      if (id.isNotEmpty && seen.add(id)) out.add((id, role));
    }

    add(reporteeId, 'Reported');
    if (reporterId != null) add(reporterId, 'Reporter');
    final subject = '${t['user_id']}';
    if (subject != reporteeId && subject != reporterId) {
      add(subject, 'Subject');
    }
    return out;
  }

  Future<void> _moderateUser(
    BuildContext context,
    ClientStore store,
    String userId, {
    required bool suspend,
  }) async {
    final duration = await promptText(
      context,
      suspend ? 'Suspend duration (e.g. 24h, 7d, or blank = indefinite)' : 'Ban duration (e.g. 24h, 7d, or blank = permanent)',
      label: 'Duration',
    );
    if (duration == null) return;
    final reason = await promptText(
      context,
      suspend ? 'Suspend reason' : 'Ban reason',
      label: 'Reason',
    );
    if (reason == null) return;
    var secs = 0;
    final d = duration.trim();
    if (d.isNotEmpty) {
      final m = RegExp(r'^(\d+)\s*([smhd]?)$').firstMatch(d.toLowerCase());
      if (m == null) {
        if (mounted) showSnack(context, 'Unrecognised duration — use e.g. 24h or 7d');
        return;
      }
      final n = int.parse(m.group(1)!);
      secs = switch (m.group(2)) {
        's' => n,
        'm' => n * 60,
        'h' => n * 3600,
        'd' => n * 86400,
        _ => n * 86400,
      };
    }
    try {
      if (suspend) {
        await store.api.post('/admin/users/$userId/restrict', {
          'action': 'suspend',
          if (secs > 0) 'duration_secs': secs,
          'reason': reason.trim(),
        });
      } else {
        await store.api.post('/admin/users/$userId/ban', {
          'reason': reason.trim(),
          if (secs > 0) 'duration_secs': secs,
        });
      }
      if (mounted) showSnack(context, '${suspend ? 'Suspended' : 'Banned'} $userId');
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    }
  }

  /// Lift active moderation on a user — offers unsuspend and/or unban.
  Future<void> _liftModeration(
    BuildContext context,
    ClientStore store,
    String userId,
  ) async {
    final choice = await _pick(
      context,
      'Lift moderation for $userId',
      ['Unsuspend account', 'Lift platform ban', 'Both'],
    );
    if (choice == null || !mounted) return;
    try {
      if (choice != 'Lift platform ban') {
        await store.api.post('/admin/users/$userId/restrict', {
          'action': 'unsuspend',
        });
      }
      if (choice != 'Unsuspend account') {
        await store.api.delete('/admin/users/$userId/ban');
      }
      if (mounted) showSnack(context, 'Moderation lifted for $userId');
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    }
  }

  Future<String?> _pick(BuildContext context, String title, List<String> options) {
    return showAppDialog<String>(
      context,
      title: title,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final o in options)
            ListTile(
              dense: true,
              title: Text(o),
              onTap: () => Navigator.pop(context, o),
            ),
        ],
      ),
      actions: const [],
    );
  }

  Widget _chip(BuildContext context, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: context.cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(text, style: const TextStyle(fontSize: 11)),
  );

  Widget _label(BuildContext context, String text) => Text(
    tr(text),
    style: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: context.cs.onSurfaceVariant,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final canManage = store.canAdmin(ClientStore.adminManageReports);
    final tickets = _tickets;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminPageHeader(
          title: 'Tickets',
          subtitle: 'Support tickets linked to reports and user issues',
          actions: [
            if (canManage)
              FilledButton.tonalIcon(
                onPressed: _createTicket,
                icon: const Icon(Icons.add, size: 18),
                label: Text(tr('New ticket')),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.md),
          child: Wrap(
            spacing: 8,
            children: [
              for (final s in [
                ('', 'All'),
                ('open', 'Open'),
                ('in_progress', 'In progress'),
                ('resolved', 'Resolved'),
                ('closed', 'Closed'),
              ])
                FilterChip(
                  label: Text(tr(s.$2)),
                  selected: _status == s.$1,
                  onSelected: (_) {
                    setState(() => _status = s.$1);
                    _load();
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: Gap.sm),
        Expanded(
          child: _error != null
              ? adminEmptyOrError(_error, false, '')
              : tickets == null
              ? const Center(child: CircularProgressIndicator())
              : tickets.isEmpty
              ? adminEmptyOrError(null, false, tr('No tickets.'))
              : AdminListScaffold(
                  children: [
                    for (final t in tickets)
                      CategoryButton(
                        icon: Icon(
                          switch (t['status']) {
                            'open' => Icons.markunread_outlined,
                            'in_progress' => Icons.pending_outlined,
                            'resolved' => Icons.check_circle_outline,
                            _ => Icons.lock_outline,
                          },
                        ),
                        title: Text('${t['subject']}'),
                        description: Text(
                          '${t['status'].toString().replaceAll('_', ' ')}'
                          ' • ${t['priority']}'
                          ' • ${t['user_id']}'
                          '${t['assigned_to'] != null ? ' • → ${t['assigned_to']}' : ''}'
                          ' • ${((t['messages'] as List?) ?? const []).length} msgs',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        action: const Icon(Icons.chevron_right),
                        onTap: () => openTicket(t),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _createTicket() async {
    final userId = await promptText(
      context,
      tr('New ticket'),
      label: tr('User ID'),
    );
    if (userId == null || userId.trim().isEmpty || !mounted) return;
    final subject = await promptText(
      context,
      tr('Ticket subject'),
      label: tr('Subject'),
    );
    if (subject == null || subject.trim().isEmpty || !mounted) return;
    final message = await promptText(
      context,
      tr('First message'),
      label: tr('Message'),
    );
    if (message == null || message.trim().isEmpty || !mounted) return;
    try {
      await context.read<ClientStore>().api.post('/admin/tickets', {
        'user_id': userId.trim(),
        'subject': subject.trim(),
        'message': message.trim(),
      });
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    }
  }
}
