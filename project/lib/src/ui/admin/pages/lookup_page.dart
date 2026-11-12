import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../api/client_store.dart';
import '../../../core/i18n.dart';
import '../../../theme/tokens.dart';
import '../../widgets.dart';
import '../admin_base.dart';


class LookupView extends StatefulWidget {
  const LookupView({super.key, this.initialId});
  final String? initialId;
  @override
  State<LookupView> createState() => _LookupViewState();
}

class _LookupViewState extends State<LookupView> {
  final _id = TextEditingController();
  Map<String, dynamic>? _result;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialId != null) {
      _id.text = widget.initialId!;
      _lookup();
    }
  }

  Future<void> _lookup() async {
    final id = _id.text.trim();
    if (id.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final r = await context.read<ClientStore>().api.get(
        '/admin/lookup/${Uri.encodeComponent(id)}',
      ) as Map;
      if (mounted) {
        setState(() {
          _result = r.cast<String, dynamic>();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorText(e);
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return AdminListScaffold(
      children: [
        Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _id,
                  decoration: InputDecoration(
                    labelText: tr('User, server, or channel ID'),
                    isDense: true,
                    border: const OutlineInputBorder(),
                    suffixIcon: _loading
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                  ),
                  onSubmitted: (_) => _lookup(),
                ),
              ),
              const SizedBox(width: Gap.sm),
              FilledButton(onPressed: _loading ? null : _lookup, child: Text(tr('Look up'))),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.md),
            child: Text(_error!, style: TextStyle(color: context.cs.error)),
          ),
        if (r != null)
          Card(
            margin: const EdgeInsets.all(Gap.md),
            child: Padding(
              padding: const EdgeInsets.all(Gap.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Chip(label: Text('${r['type']}')),
                      const SizedBox(width: Gap.sm),
                      Expanded(
                        child: SelectableText(
                          '${r['id']}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Gap.sm),
                  for (final kv in r.entries)
                    if (kv.key != 'type' && kv.key != 'id')
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 110,
                              child: Text(
                                kv.key,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text('${kv.value ?? '—'}'),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

