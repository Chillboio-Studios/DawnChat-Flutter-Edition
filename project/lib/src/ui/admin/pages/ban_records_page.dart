import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../api/client_store.dart';
import '../../../core/i18n.dart';
import '../../../theme/tokens.dart';
import '../../widgets.dart';
import '../admin_base.dart';
import '../../modals/app_dialog.dart';


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
      return adminEmptyOrError(_error, bans == null, tr('No ban records.'));
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
          adminEmptyOrError(null, false, tr('No ban records.')),
      ],
    );
  }
}

