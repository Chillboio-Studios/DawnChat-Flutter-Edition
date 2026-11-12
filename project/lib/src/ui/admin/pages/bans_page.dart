import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../api/client_store.dart';
import '../../../core/i18n.dart';
import '../../widgets.dart';
import '../admin_base.dart';

/// Platform-wide ban list with unban actions.
class BansView extends StatefulWidget {
  const BansView({super.key});

  @override
  State<BansView> createState() => _BansViewState();
}

class _BansViewState extends State<BansView> {
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
        const AdminPageHeader(
          title: 'Platform Bans',
          subtitle: 'Users banned from the entire platform',
        ),
        Expanded(
          child: _error != null
              ? adminEmptyOrError(_error, false, '')
              : users == null
              ? const Center(child: CircularProgressIndicator())
              : users.isEmpty
              ? adminEmptyOrError(null, false, tr('No banned users.'))
              : AdminListScaffold(
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
                              await store.api.delete(
                                '/admin/users/${u['_id']}/ban',
                              );
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
        ),
      ],
    );
  }
}
