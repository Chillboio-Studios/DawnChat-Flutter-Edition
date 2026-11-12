import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../api/client_store.dart';
import '../../../core/i18n.dart';
import '../../../router.dart';
import '../../widgets.dart';
import '../../../theme/tokens.dart';
import '../admin_base.dart';
import '../../modals/app_dialog.dart';

/// Safety reports queue with detail view, notes and ticket creation.
class ReportsView extends StatefulWidget {
  const ReportsView({super.key, this.focusReportId});
  final String? focusReportId;

  @override
  State<ReportsView> createState() => ReportsViewState();
}

class ReportsViewState extends State<ReportsView> {
  String _status = '';
  List<Map<String, dynamic>>? _reports;
  String? _error;
  String? _focused;

  @override
  void initState() {
    super.initState();
    _focused = widget.focusReportId;
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await context.read<ClientStore>().api.get(
        '/admin/reports',
        query: {
          'limit': '200',
          if (_status.isNotEmpty) 'status': _status,
        },
      ) as List;
      if (mounted) {
        setState(() {
          _reports = r.map((e) => (e as Map).cast<String, dynamic>()).toList();
          _error = null;
        });
        if (_focused != null) {
          final id = _focused!;
          _focused = null;
          final match = _reports!.where((r) => '${r['id']}' == id);
          if (match.isNotEmpty) openReport(match.first);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _patch(Map<String, dynamic> r, Map<String, dynamic> body) async {
    try {
      await context.read<ClientStore>().api.patch(
        '/admin/reports/${r['id']}',
        body,
      );
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    }
  }

  Future<void> _createTicket(Map<String, dynamic> r) async {
    final subject = await promptText(
      context,
      tr('Open ticket for this report'),
      label: tr('Subject'),
      initial: 'Report ${r['id']}',
    );
    if (subject == null || !mounted) return;
    try {
      await context.read<ClientStore>().api.post('/admin/tickets', {
        'user_id': r['author_id'],
        'report_id': r['id'],
        'subject': subject,
        'message': r['additional_context'] ?? r['content'] ?? 'Report investigation',
      });
      if (mounted) showSnack(context, tr('Ticket created.'));
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    }
  }

  /// Reports auto-open a ticket — jump straight to it.
  Future<void> _viewTicket(Map<String, dynamic> r) async {
    try {
      final tickets = await context.read<ClientStore>().api.get(
        '/admin/tickets',
        query: {'report_id': '${r['id']}', 'limit': '10'},
      ) as List;
      if (!mounted) return;
      if (tickets.isEmpty) {
        showSnack(context, tr('No ticket linked to this report yet.'));
        return;
      }
      final id = '${(tickets.first as Map)['_id']}';
      context.goPath('/admin?s=tickets&tid=$id');
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    }
  }

  Future<void> openReport(Map<String, dynamic> r) async {
    final store = context.read<ClientStore>();
    final canManage = store.canAdmin(ClientStore.adminManageReports);
    final notes = TextEditingController(text: '${r['notes'] ?? ''}');
    var status = '${r['status']}';

    await showAppDialog<void>(
      context,
      title: 'Report ${r['id']}',
      maxWidth: 640,
      content: StatefulBuilder(
        builder: (context, setDlg) => SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv('Reporter', '${r['author_id']}'),
              _kv('Status', status),
              if (r['status_detail'] != null)
                _kv('Detail', '${r['status_detail']}'),
              const SizedBox(height: 8),
              Text(
                '${r['additional_context'] ?? ''}',
                style: const TextStyle(fontSize: 14),
              ),
              if (r['content'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Content: ${r['content']}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              if (canManage) ...[
                TextField(
                  controller: notes,
                  maxLines: 3,
                  maxLength: 2000,
                  decoration: InputDecoration(
                    labelText: tr('Internal notes'),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    Text(
                      '${tr('Current')}: $status',
                      style: const TextStyle(fontSize: 12),
                    ),
                    for (final s in ['Resolved', 'Rejected'])
                      ChoiceChip(
                        label: Text(s),
                        selected: status == s,
                        onSelected: canManage
                            ? (_) => setDlg(() => status = s)
                            : null,
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
              final action = status == 'Rejected' ? 'reject' : 'resolve';
              await _patch(r, {
                'action': action,
                'notes': notes.text,
                if (status == 'Rejected') 'rejection_reason': notes.text,
              });
              return null;
            },
          ),
        if (canManage)
          DlgAction(
            tr('Open ticket'),
            onPressed: () async {
              await _createTicket(r);
              return null;
            },
          ),
        if (canManage)
          DlgAction(
            tr('View ticket'),
            onPressed: () async {
              await _viewTicket(r);
              return null;
            },
          ),
      ],
    );
    notes.dispose();
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            tr(k),
            style: TextStyle(
              fontSize: 12,
              color: context.cs.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final reports = _reports;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminPageHeader(
          title: 'Safety Reports',
          subtitle: 'User-submitted reports awaiting review',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.md),
          child: Wrap(
            spacing: 8,
            children: [
              for (final s in [
                ('', 'All'),
                ('Created', 'Open'),
                ('Resolved', 'Resolved'),
                ('Rejected', 'Rejected'),
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
              : reports == null
              ? const Center(child: CircularProgressIndicator())
              : reports.isEmpty
              ? adminEmptyOrError(null, false, tr('No reports.'))
              : AdminListScaffold(
                  children: [
                    for (final r in reports)
                      CategoryButton(
                        icon: Icon(
                          r['status'] == 'Created'
                              ? Icons.flag
                              : Icons.flag_outlined,
                        ),
                        title: Text('${r['status']} — ${r['author_id']}'),
                        description: Text(
                          '${r['additional_context'] ?? ''}'
                          '${r['content'] != null ? ' • ${r['content']}' : ''}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        action: const Icon(Icons.chevron_right),
                        onTap: () => openReport(r),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
