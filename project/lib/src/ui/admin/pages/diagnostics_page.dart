import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../api/client_store.dart';
import '../../../api/transport.dart';
import '../../../core/i18n.dart';
import '../../../theme/tokens.dart';
import '../admin_base.dart';


class DiagnosticsView extends StatefulWidget {
  const DiagnosticsView({super.key});
  @override
  State<DiagnosticsView> createState() => _DiagnosticsViewState();
}

class _DiagnosticsViewState extends State<DiagnosticsView> {
  final _results = <String, (String, int?)>{};
  bool _running = false;

  Future<void> _check(String name, String url) async {
    final sw = Stopwatch()..start();
    try {
      final res = await sendRequest('GET', url)
          .timeout(const Duration(seconds: 8));
      sw.stop();
      _results[name] = ('HTTP ${res.status}', sw.elapsedMilliseconds);
    } catch (e) {
      sw.stop();
      _results[name] = ('${e.runtimeType}', sw.elapsedMilliseconds);
    }
  }

  Future<void> _run() async {
    setState(() => _running = true);
    _results.clear();
    final api = context.read<ClientStore>().api;
    final ws = api.config?.ws ?? '';
    final targets = <String, String>{
      'API': '${api.baseUrl}/',
      if (ws.isNotEmpty) 'WebSocket': ws,
      if (api.config?.autumnUrl.isNotEmpty ?? false)
        'Autumn': '${api.config!.autumnUrl}/',
    };
    await Future.wait([for (final e in targets.entries) _check(e.key, e.value)]);
    if (mounted) setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    return AdminListScaffold(
      children: [
        Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('Check connectivity to platform services.'),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: Gap.md),
              FilledButton.icon(
                onPressed: _running ? null : _run,
                icon: _running
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.network_check, size: 18),
                label: Text(tr('Run diagnostics')),
              ),
              const SizedBox(height: Gap.md),
              for (final e in _results.entries)
                ListTile(
                  dense: true,
                  leading: Icon(
                    e.value.$1.startsWith('HTTP 2')
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    size: 20,
                    color: e.value.$1.startsWith('HTTP 2')
                        ? Colors.green
                        : context.cs.error,
                  ),
                  title: Text(e.key),
                  subtitle: Text(e.value.$1),
                  trailing: Text('${e.value.$2 ?? 0}ms'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
