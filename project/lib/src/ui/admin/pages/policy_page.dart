import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../api/client_store.dart';
import '../../../core/i18n.dart';
import '../../../theme/tokens.dart';
import '../../widgets.dart';
import '../admin_base.dart';

/// Publish platform policy changes (ToS / privacy updates). Every client
/// shows the notice on next connect until acknowledged.
class PolicyView extends StatefulWidget {
  const PolicyView({super.key});

  @override
  State<PolicyView> createState() => PolicyViewState();
}

class PolicyViewState extends State<PolicyView> {
  final _description = TextEditingController();
  final _url = TextEditingController();
  List<Map<String, dynamic>>? _changes;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _description.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await context.read<ClientStore>().api.get('/admin/policy') as List;
      if (mounted) {
        setState(() {
          _changes = r.map((e) => (e as Map).cast<String, dynamic>()).toList();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _publish() async {
    final description = _description.text.trim();
    final url = _url.text.trim();
    if (description.isEmpty || url.isEmpty) {
      showSnack(context, tr('Description and URL are required.'));
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<ClientStore>().api.post('/admin/policy', {
        'description': description,
        'url': url,
      });
      _description.clear();
      _url.clear();
      await _load();
      if (mounted) showSnack(context, tr('Policy change published.'));
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final canPublish = store.canAdmin(ClientStore.adminBroadcast);
    final changes = _changes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminPageHeader(
          title: 'Policy',
          subtitle:
              'Publish ToS / privacy updates — every client sees the notice until acknowledged',
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: Gap.md),
            children: [
              if (canPublish) ...[
                Text(
                  tr('New policy change'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: context.cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _description,
                  maxLines: 3,
                  maxLength: 2000,
                  decoration: InputDecoration(
                    labelText: tr('Notice shown to users'),
                    hintText: tr('e.g. We updated our Terms of Service and Privacy Policy.'),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _url,
                  maxLength: 500,
                  decoration: InputDecoration(
                    labelText: tr('Details URL'),
                    hintText: 'https://www.chillboiostudios.com/terms',
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _publish,
                    icon: const Icon(Icons.campaign_outlined, size: 18),
                    label: Text(tr('Publish notice')),
                  ),
                ),
                const Divider(height: 32),
              ],
              Text(
                tr('Published changes'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: context.cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              if (_error != null)
                adminEmptyOrError(_error, false, '')
              else if (changes == null)
                const Center(child: CircularProgressIndicator())
              else if (changes.isEmpty)
                adminEmptyOrError(null, false, tr('No policy changes published.'))
              else
                AdminListScaffold(
                  children: [
                    for (final c in changes)
                      CategoryButton(
                        icon: const Icon(Icons.gavel_outlined),
                        title: Text('${c['description']}'),
                        description: Text(
                          '${c['url']}'
                          ' • ${(c['created_time'] as String? ?? '').split('T').first}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}
