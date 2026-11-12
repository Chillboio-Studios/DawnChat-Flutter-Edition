import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../api/client_store.dart';
import '../../../core/i18n.dart';
import '../../../theme/tokens.dart';
import '../../widgets.dart';
import '../admin_base.dart';


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
      return adminEmptyOrError(_error, entries == null, tr('No audit entries.'));
    }
    if (entries.isEmpty) {
      return adminEmptyOrError(null, false, tr('No audit entries.'));
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

