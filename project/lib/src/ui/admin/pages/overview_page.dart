import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../api/client_store.dart';
import '../../../core/i18n.dart';
import '../../../theme/tokens.dart';
import '../../widgets.dart';
import '../admin_base.dart';


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
      return adminEmptyOrError(_error, stats == null, tr('No data.'));
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

