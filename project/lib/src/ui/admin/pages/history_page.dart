import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../api/client_store.dart';
import '../../../core/i18n.dart';
import '../../../theme/tokens.dart';
import '../../widgets.dart';
import '../admin_base.dart';


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
      return adminEmptyOrError(_error, entries == null, tr('No history entries.'));
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
          adminEmptyOrError(null, false, tr('No history entries.')),
      ],
    );
  }
}
