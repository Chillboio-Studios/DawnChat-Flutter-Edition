import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../api/client_store.dart';
import '../../../core/i18n.dart';
import '../../../theme/tokens.dart';
import '../../widgets.dart';
import '../admin_base.dart';


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
      return adminEmptyOrError(_error, strikes == null, tr('No strikes.'));
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

