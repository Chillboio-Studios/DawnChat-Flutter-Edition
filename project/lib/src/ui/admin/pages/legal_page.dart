import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../api/client_store.dart';
import '../../../core/i18n.dart';
import '../../../theme/tokens.dart';
import '../../modals/app_dialog.dart';
import '../../widgets.dart';
import '../admin_base.dart';

/// Law-enforcement / legal request pipeline — log, triage and track
/// subpoenas, EDRs, preservation requests and court orders.
class LegalView extends StatefulWidget {
  const LegalView({super.key});

  @override
  State<LegalView> createState() => LegalViewState();
}

class LegalViewState extends State<LegalView> {
  List<Map<String, dynamic>>? _requests;
  String? _error;

  static const _types = ['subpoena', 'edr', 'preservation', 'court_order', 'other'];
  static const _statuses = ['received', 'reviewing', 'fulfilled', 'rejected', 'withdrawn'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await context.read<ClientStore>().api.get('/admin/legal') as List;
      if (mounted) {
        setState(() {
          _requests = r.map((e) => (e as Map).cast<String, dynamic>()).toList();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _create() async {
    final type = await _pick('Request type', _types);
    if (type == null || !mounted) return;
    final agency = await promptText(context, 'Issuing agency / court', label: 'Agency');
    if (agency == null || agency.trim().isEmpty || !mounted) return;
    final reference = await promptText(context, 'Case / reference number', label: 'Reference (optional)');
    if (reference == null || !mounted) return;
    final description = await promptText(
      context,
      'Legal request details',
      label: 'What is requested + legal basis',
    );
    if (description == null || description.trim().isEmpty || !mounted) return;
    try {
      await context.read<ClientStore>().api.post('/admin/legal', {
        'request_type': type,
        'agency': agency.trim(),
        'reference': reference.trim(),
        'description': description.trim(),
      });
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    }
  }

  Future<String?> _pick(String title, List<String> options) {
    return showAppDialog<String>(
      context,
      title: title,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final o in options)
            ListTile(
              dense: true,
              title: Text(o.replaceAll('_', ' ')),
              onTap: () => Navigator.pop(context, o),
            ),
        ],
      ),
      actions: const [],
    );
  }

  Future<void> openRequest(Map<String, dynamic> r) async {
    final store = context.read<ClientStore>();
    final canManage = store.canAdmin(ClientStore.adminManageReports);
    var status = '${r['status']}';
    var assigned = '${r['assigned_to'] ?? ''}';
    final notes = TextEditingController(text: '${r['staff_notes'] ?? ''}');

    await showAppDialog<void>(
      context,
      title: '${r['request_type']} — ${r['agency']}',
      maxWidth: 620,
      content: StatefulBuilder(
        builder: (context, setDlg) => SizedBox(
          width: 540,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _chip(context, 'Ref: ${r['reference'] ?? '—'}'),
                  if (r['due_at'] != null)
                    _chip(context, 'Due: ${(r['due_at'] as String).split('T').first}'),
                  _chip(context, 'By: ${r['created_by']}'),
                ],
              ),
              const SizedBox(height: 10),
              Text('${r['description']}', style: const TextStyle(fontSize: 14)),
              if (canManage) ...[
                const Divider(height: 20),
                TextField(
                  controller: notes,
                  maxLines: 3,
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
                    for (final s in _statuses)
                      ChoiceChip(
                        label: Text(s.replaceAll('_', ' ')),
                        selected: status == s,
                        onSelected: (_) => setDlg(() => status = s),
                      ),
                    _label(context, 'Assign'),
                    ActionChip(
                      avatar: const Icon(Icons.person_outline, size: 16),
                      label: Text(assigned.isEmpty ? 'Unassigned' : assigned),
                      onPressed: () async {
                        final id = await promptText(context, 'Assign to user ID', label: 'User ID');
                        if (id != null) setDlg(() => assigned = id.trim());
                      },
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
              await store.api.patch('/admin/legal/${r['_id']}', {
                'status': status,
                'assigned_to': assigned.isEmpty ? null : assigned,
                'staff_notes': notes.text,
              });
              await _load();
              return null;
            },
          ),
      ],
    );
    notes.dispose();
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
    final requests = _requests;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminPageHeader(
          title: 'Legal',
          subtitle: 'Law-enforcement and legal requests — subpoenas, EDRs, preservation',
          actions: [
            if (canManage)
              FilledButton.tonalIcon(
                onPressed: _create,
                icon: const Icon(Icons.add, size: 18),
                label: Text(tr('Log request')),
              ),
          ],
        ),
        const SizedBox(height: Gap.sm),
        Expanded(
          child: _error != null
              ? adminEmptyOrError(_error, false, '')
              : requests == null
              ? const Center(child: CircularProgressIndicator())
              : requests.isEmpty
              ? adminEmptyOrError(null, false, tr('No legal requests.'))
              : AdminListScaffold(
                  children: [
                    for (final r in requests)
                      CategoryButton(
                        icon: Icon(
                          switch (r['status']) {
                            'fulfilled' => Icons.check_circle_outline,
                            'rejected' || 'withdrawn' => Icons.cancel_outlined,
                            'reviewing' => Icons.pending_outlined,
                            _ => Icons.gavel_outlined,
                          },
                        ),
                        title: Text('${r['agency']} — ${r['request_type']}'),
                        description: Text(
                          '${r['status'].toString().replaceAll('_', ' ')}'
                          '${r['reference'] != null && '${r['reference']}'.isNotEmpty ? ' • ${r['reference']}' : ''}'
                          ' • ${r['request_type']}'
                          '${r['due_at'] != null ? ' • due ${(r['due_at'] as String).split('T').first}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        action: const Icon(Icons.chevron_right),
                        onTap: () => openRequest(r),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
