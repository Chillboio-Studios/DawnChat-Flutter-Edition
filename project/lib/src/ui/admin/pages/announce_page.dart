import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../api/client_store.dart';
import '../../../core/i18n.dart';
import '../../../theme/tokens.dart';
import '../../net_image.dart';
import '../../widgets.dart';
import '../admin_base.dart';

/// Platform announcements — ported from DawnAdmin's CommunicationView.
/// Two tabs: compose (recipient mode, user picker, rich embed designer)
/// and broadcast history (from the platform audit log).
class AnnounceView extends StatefulWidget {
  const AnnounceView({super.key});
  @override
  State<AnnounceView> createState() => _AnnounceViewState();
}

enum _RecipientMode { all, users, channel }

class _AnnounceViewState extends State<AnnounceView> {
  int _tab = 0;
  _RecipientMode _mode = _RecipientMode.all;
  final _content = TextEditingController();
  final _channel = TextEditingController();
  final _sendAt = TextEditingController();
  final _embedTitle = TextEditingController();
  final _embedDesc = TextEditingController();
  final _embedUrl = TextEditingController();
  String _embedColour = '#f59e0b';
  bool _showEmbed = false;
  bool _sending = false;

  // Specific-user picker state
  final _userSearch = TextEditingController();
  List<Map<String, dynamic>>? _userResults;
  final Set<String> _selected = {};
  final _userDetails = <String, Map<String, dynamic>>{};

  // History state
  List<Map<String, dynamic>>? _history;
  String? _historyError;

  static const _colourPresets = [
    '#f59e0b',
    '#3b82f6',
    '#10b981',
    '#8b5cf6',
    '#ef4444',
  ];

  @override
  void initState() {
    super.initState();
    _searchUsers('');
    _loadHistory();
  }

  @override
  void dispose() {
    for (final c in [
      _content,
      _channel,
      _sendAt,
      _embedTitle,
      _embedDesc,
      _embedUrl,
      _userSearch,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _searchUsers(String q) async {
    try {
      final r = await context.read<ClientStore>().api.get(
        '/admin/users',
        query: {
          if (q.trim().isNotEmpty) 'q': q.trim(),
          'disabled': 'false',
          'deleted': 'false',
          'limit': '30',
        },
      ) as List;
      if (mounted) {
        setState(() {
          _userResults = r.map((e) => (e as Map).cast<String, dynamic>()).toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _loadHistory() async {
    try {
      final r = await context.read<ClientStore>().api.get(
        '/admin/audit-logs',
        query: {'limit': '300'},
      ) as List;
      if (mounted) {
        setState(() {
          _history = r
              .map((e) => (e as Map).cast<String, dynamic>())
              .where((e) => '${e['action']}'.startsWith('announce'))
              .toList();
          _historyError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _historyError = errorText(e));
    }
  }

  Future<void> _send() async {
    final content = _content.text.trim();
    if (content.isEmpty) {
      showSnack(context, tr('Message cannot be empty.'));
      return;
    }
    if (_mode == _RecipientMode.users && _selected.isEmpty) {
      showSnack(context, tr('Select at least one recipient.'));
      return;
    }
    if (_mode == _RecipientMode.channel && _channel.text.trim().isEmpty) {
      showSnack(context, tr('Provide a channel ID.'));
      return;
    }

    final hasEmbed = _embedTitle.text.trim().isNotEmpty ||
        _embedDesc.text.trim().isNotEmpty ||
        _embedUrl.text.trim().isNotEmpty;

    setState(() => _sending = true);
    try {
      final res = await context.read<ClientStore>().api.post('/admin/announce', {
        'content': content,
        if (_mode == _RecipientMode.channel) 'channel_id': _channel.text.trim(),
        if (_mode == _RecipientMode.users) 'user_ids': _selected.toList(),
        if (_mode == _RecipientMode.all) 'all_users': true,
        if (_sendAt.text.trim().isNotEmpty) 'send_at': _sendAt.text.trim(),
        if (hasEmbed) ...{
          if (_embedTitle.text.trim().isNotEmpty)
            'embed_title': _embedTitle.text.trim(),
          if (_embedDesc.text.trim().isNotEmpty)
            'embed_description': _embedDesc.text.trim(),
          if (_embedUrl.text.trim().isNotEmpty)
            'embed_url': _embedUrl.text.trim(),
          'embed_colour': _embedColour,
        },
      }) as Map;
      if (mounted) {
        showSnack(
          context,
          res['scheduled'] == true
              ? tr('Announcement scheduled.')
              : tr('Delivered to {n} recipient(s).', {'n': res['sent'] ?? 0}),
        );
        _content.clear();
        _loadHistory();
      }
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminPageHeader(
          title: 'Announcements',
          subtitle:
              'Dispatch announcements to users via the system account. Delivered as regular messages with websocket events, unread tracking and push notifications.',
          actions: [
            _tabButton(0, Icons.campaign_outlined, 'Compose'),
            _tabButton(1, Icons.history, 'History'),
          ],
        ),
        Expanded(
          child: _tab == 0 ? _buildCompose(cs) : _buildHistory(cs),
        ),
      ],
    );
  }

  Widget _tabButton(int i, IconData icon, String label) {
    final selected = _tab == i;
    final cs = context.cs;
    return Material(
      color: selected ? cs.secondaryContainer : Colors.transparent,
      borderRadius: br(Radius_.lg),
      child: InkWell(
        borderRadius: br(Radius_.lg),
        onTap: () => setState(() => _tab = i),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                tr(label),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- Compose tab ----------------

  Widget _buildCompose(ColorScheme cs) {
    final users = _userResults ?? const [];
    return AdminListScaffold(
      children: [
        // Sender card — system account
        _card(
          cs,
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.secondaryContainer,
                  borderRadius: br(Radius_.lg),
                ),
                child: Icon(Icons.campaign, size: 20, color: cs.onSecondaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'DawnChat System',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _miniChip(cs, 'SYSTEM', cs.secondaryContainer, cs.onSecondaryContainer),
                        const SizedBox(width: 6),
                        _miniChip(cs, 'EVENTS', cs.surfaceContainerHighest, cs.onSurfaceVariant),
                      ],
                    ),
                    Text(
                      'Messages are authored by the system account and delivered with full websocket events.',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.md),

        // Recipient mode
        _card(
          cs,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _stepLabel(cs, '1. Select recipients'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _modeCard(
                    cs,
                    mode: _RecipientMode.all,
                    icon: Icons.people_outline,
                    title: 'All users',
                    subtitle: 'DM every active non-bot, non-banned account',
                  ),
                  _modeCard(
                    cs,
                    mode: _RecipientMode.users,
                    icon: Icons.person_search_outlined,
                    title: 'Specific users',
                    subtitle: '${_selected.length} selected',
                  ),
                  _modeCard(
                    cs,
                    mode: _RecipientMode.channel,
                    icon: Icons.tag,
                    title: 'Channel',
                    subtitle: 'Post in a channel by ID',
                  ),
                ],
              ),
              if (_mode == _RecipientMode.users) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _userSearch,
                  decoration: InputDecoration(
                    hintText: tr('Search users to add...'),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                  ),
                  onChanged: (v) => _searchUsers(v),
                ),
                if (_selected.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final id in _selected)
                          InputChip(
                            label: Text(
                              _userDetails[id] != null
                                  ? '${_userDetails[id]!['username']}#${_userDetails[id]!['discriminator']}'
                                  : id,
                              style: const TextStyle(fontSize: 12),
                            ),
                            onDeleted: () => setState(() => _selected.remove(id)),
                            deleteIconColor: cs.onSurfaceVariant,
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final u in users)
                        if (!_selected.contains('${u['_id']}'))
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: NetImage(
                              context
                                      .read<ClientStore>()
                                      .api
                                      .fileUrl('avatars', u['avatar'] as Map?, width: 96) ??
                                  '',
                              width: 28,
                              height: 28,
                            ),
                            title: Text(
                              '${u['username']}#${u['discriminator']}',
                              style: const TextStyle(fontSize: 13),
                            ),
                            subtitle: Text(
                              '${u['_id']}',
                              style: const TextStyle(
                                fontSize: 10,
                                fontFamily: 'monospace',
                              ),
                            ),
                            trailing: u['privileged'] == true
                                ? _miniChip(cs, 'ADMIN', cs.surfaceContainerHighest, cs.onSurfaceVariant)
                                : null,
                            onTap: () => setState(() {
                              _selected.add('${u['_id']}');
                              _userDetails['${u['_id']}'] = u;
                            }),
                          ),
                    ],
                  ),
                ),
              ],
              if (_mode == _RecipientMode.channel) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _channel,
                  decoration: InputDecoration(
                    labelText: tr('Channel ID'),
                    hintText: '01J...',
                    isDense: true,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Gap.md),

        // Message content + embed designer
        _card(
          cs,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: _stepLabel(cs, '2. Message content')),
                  Text(
                    '${_content.text.length} chars',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _content,
                maxLines: 6,
                minLines: 4,
                maxLength: 4000,
                decoration: InputDecoration(
                  hintText: tr(
                    'Type your official announcement here (supports markdown, emojis, links)...',
                  ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _showEmbed = !_showEmbed),
                  icon: Icon(
                    _showEmbed ? Icons.expand_less : Icons.palette_outlined,
                    size: 16,
                  ),
                  label: Text(
                    _showEmbed
                        ? tr('Hide rich embed')
                        : tr('Add rich card embed'),
                  ),
                ),
              ),
              if (_showEmbed) ...[
                TextField(
                  controller: _embedTitle,
                  maxLength: 100,
                  decoration: InputDecoration(
                    labelText: tr('Embed title'),
                    hintText: 'e.g. Platform Maintenance Notice',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _embedUrl,
                  maxLength: 256,
                  decoration: InputDecoration(
                    labelText: tr('Embed URL (optional)'),
                    hintText: 'https://dawn-chat.com/changelog',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _embedDesc,
                  maxLines: 2,
                  maxLength: 2000,
                  decoration: InputDecoration(
                    labelText: tr('Embed description'),
                    hintText: 'Detailed announcement card explanation...',
                    alignLabelWithHint: true,
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Text(tr('Embed accent colour'), style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final c in _colourPresets)
                      GestureDetector(
                        onTap: () => setState(() => _embedColour = c),
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: Color(int.parse('FF${c.substring(1)}', radix: 16)),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _embedColour == c ? cs.onSurface : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: TextEditingController(text: _embedColour)
                          ..selection = TextSelection.collapsed(
                            offset: _embedColour.length,
                          ),
                        maxLength: 7,
                        style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                        decoration: const InputDecoration(isDense: true, counterText: ''),
                        onChanged: (v) => _embedColour = v,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              _stepLabel(cs, '3. Schedule (optional)'),
              const SizedBox(height: 8),
              TextField(
                controller: _sendAt,
                decoration: InputDecoration(
                  labelText: tr('Send at (ISO-8601)'),
                  hintText: '2025-01-01T12:00:00Z — leave empty to send now',
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.md),

        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send, size: 18),
            label: Text(
              _sendAt.text.trim().isEmpty
                  ? tr('Broadcast announcement')
                  : tr('Schedule announcement'),
            ),
          ),
        ),
        const SizedBox(height: Gap.lg),
      ],
    );
  }

  // ---------------- History tab ----------------

  Widget _buildHistory(ColorScheme cs) {
    final history = _history;
    if (_historyError != null) {
      return adminEmptyOrError(_historyError, false, '');
    }
    if (history == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (history.isEmpty) {
      return adminEmptyOrError(null, false, tr('No broadcasts recorded yet.'));
    }
    return AdminListScaffold(
      children: [
        for (final e in history)
          CategoryButton(
            icon: Icon(
              e['action'] == 'announce.schedule'
                  ? Icons.schedule_outlined
                  : Icons.campaign_outlined,
            ),
            title: Text('${e['action']} — ${e['actor_id']}'),
            description: Text(
              '${e['details'] ?? ''}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            action: Text(
              (e['created_at'] as String? ?? '').split('T').first,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
      ],
    );
  }

  Widget _card(ColorScheme cs, {required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(Gap.lg),
    decoration: BoxDecoration(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: br(Radius_.xl),
      border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
    ),
    child: child,
  );

  Widget _stepLabel(ColorScheme cs, String text) => Text(
    tr(text).toUpperCase(),
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.6,
      color: cs.onSurfaceVariant,
    ),
  );

  Widget _miniChip(ColorScheme cs, String text, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: fg),
    ),
  );

  Widget _modeCard(
    ColorScheme cs, {
    required _RecipientMode mode,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final selected = _mode == mode;
    return InkWell(
      borderRadius: br(Radius_.lg),
      onTap: () => setState(() => _mode = mode),
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? cs.secondaryContainer.withValues(alpha: 0.5)
              : cs.surface,
          borderRadius: br(Radius_.lg),
          border: Border.all(
            color: selected ? cs.secondary : cs.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: selected ? cs.secondary : cs.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(title),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
