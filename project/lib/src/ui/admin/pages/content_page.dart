import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../api/client_store.dart';
import '../../../core/i18n.dart';
import '../../../theme/tokens.dart';
import '../../widgets.dart';
import '../admin_base.dart';


class ContentModView extends StatefulWidget {
  const ContentModView({super.key});
  @override
  State<ContentModView> createState() => _ContentModViewState();
}

class _ContentModViewState extends State<ContentModView> {
  final _channel = TextEditingController();
  List<Map<String, dynamic>>? _messages;
  String? _channelName;
  bool _loading = false;
  String? _error;

  Future<void> _load() async {
    final id = _channel.text.trim();
    if (id.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _messages = null;
      _channelName = null;
    });
    final api = context.read<ClientStore>().api;
    try {
      final ch = await api.get('/channels/$id') as Map;
      final msgs = await api.get(
        '/channels/$id/messages',
        query: {'limit': '50'},
      ) as List;
      if (mounted) {
        setState(() {
          _channelName = ch['name'] as String? ?? id;
          _messages = msgs
              .map((e) => (e as Map).cast<String, dynamic>())
              .toList();
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
    final msgs = _messages;
    return AdminListScaffold(
      children: [
        Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _channel,
                  decoration: InputDecoration(
                    labelText: tr('Channel ID'),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _load(),
                ),
              ),
              const SizedBox(width: Gap.sm),
              FilledButton(
                onPressed: _loading ? null : _load,
                child: Text(tr('Inspect')),
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.md),
            child: Text(_error!, style: TextStyle(color: context.cs.error)),
          ),
        if (_channelName != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.md),
            child: Text(
              tr('Channel: {name}', {'name': _channelName!}),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        if (msgs != null)
          for (final m in msgs.reversed)
            ListTile(
              dense: true,
              leading: const Icon(Icons.chat_bubble_outline, size: 20),
              title: Text('${m['author']}'),
              subtitle: Text(
                '${m['content'] ?? ''}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(
                (m['id'] as String? ?? '').substring(
                  0,
                  ((m['id'] as String? ?? '').length).clamp(0, 8),
                ),
                style: const TextStyle(fontSize: 11),
              ),
            ),
        if (msgs != null && msgs.isEmpty)
          adminEmptyOrError(null, false, tr('No messages in this channel.')),
      ],
    );
  }
}

