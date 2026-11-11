import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../api/client_store.dart';
import '../../core/links.dart';
import '../../router.dart';
import '../../state/settings_store.dart';
import '../../theme/tokens.dart';
import '../settings/settings_page.dart';
import '../widgets.dart';
import 'discover_embed_stub.dart'
    if (dart.library.js_interop) 'discover_embed_web.dart';
import 'home_page.dart';
import '../../core/i18n.dart';

/// Sends the user back to where they last were (PWA start / after dialogs).
class _GoLast extends StatefulWidget {
  const _GoLast({this.onMount});
  final void Function(BuildContext context)? onMount;
  @override
  State<_GoLast> createState() => _GoLastState();
}

class _GoLastState extends State<_GoLast> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onMount?.call(context);
      final last = context.read<SettingsStore>().lastActivePath;
      final target =
          (last == '/settings' ||
              last.startsWith('/invite/') ||
              last.startsWith('/bot/'))
          ? '/app'
          : last;
      context.go(context.href(target));
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class PwaRedirect extends StatelessWidget {
  const PwaRedirect({super.key});
  @override
  Widget build(BuildContext context) => const _GoLast();
}

class SettingsRedirect extends StatelessWidget {
  const SettingsRedirect({super.key});
  @override
  Widget build(BuildContext context) =>
      _GoLast(onMount: (c) => showSettings(c));
}

class InviteRedirect extends StatelessWidget {
  const InviteRedirect({super.key, required this.code});
  final String code;
  @override
  Widget build(BuildContext context) =>
      _GoLast(onMount: (c) => _showInvite(c, code));
}

class BotRedirect extends StatelessWidget {
  const BotRedirect({super.key, required this.code});
  final String code;
  @override
  Widget build(BuildContext context) =>
      _GoLast(onMount: (c) => _showBot(c, code));
}

Future<void> _showInvite(BuildContext context, String code) async {
  final store = context.read<ClientStore>();
  try {
    final invite = await store.fetchInvite(code);
    if (!context.mounted) return;
    final name =
        (invite['server_name'] ?? invite['channel_name'] ?? 'this community')
            as String;
    final members = invite['member_count'];
    final joined =
        invite['type'] == 'Server' &&
        store.servers.containsKey(invite['server_id']);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text("You've been invited to join"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconAvatar(
              url: store.api.fileUrl(
                'icons',
                (invite['server_icon'] ?? invite['channel_icon']) as Map?,
                width: 128,
              ),
              name: name,
              size: 64,
            ),
            const SizedBox(height: 12),
            Text(
              name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            if (members != null) Text('$members members'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(joined ? 'Open' : 'Join'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    if (joined) {
      context.goPath('/server/${invite['server_id']}');
      return;
    }
    final res = await store.joinInvite(code);
    if (!context.mounted) return;
    final server = res['server'] as Map?;
    if (server != null) {
      store.servers[server['_id']] = server.cast<String, dynamic>();
      for (final c in (res['channels'] as List? ?? [])) {
        store.channels[c['_id']] = (c as Map).cast<String, dynamic>();
      }
      context.goPath('/server/${server['_id']}');
    } else if (res['channel'] != null) {
      final ch = (res['channel'] as Map).cast<String, dynamic>();
      store.channels[ch['_id']] = ch;
      context.goPath('/channel/${ch['_id']}');
    }
  } catch (e) {
    if (context.mounted) showSnack(context, errorText(e));
  }
}

Future<void> _showBot(BuildContext context, String id) async {
  final store = context.read<ClientStore>();
  try {
    final bot = ((await store.api.get('/bots/$id/invite')) as Map)
        .cast<String, dynamic>();
    if (!context.mounted) return;
    final mine = store.serverList
        .where((s) => s['owner'] == store.userId)
        .toList();
    String? picked = mine.isEmpty ? null : mine.first['_id'] as String;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text('Add ${bot['username']}'),
          content: mine.isEmpty
              ? const Text('You do not own any servers to add this bot to.')
              : DropdownButton<String>(
                  isExpanded: true,
                  value: picked,
                  items: [
                    for (final s in mine)
                      DropdownMenuItem(
                        value: s['_id'] as String,
                        child: Text(s['name'] as String),
                      ),
                  ],
                  onChanged: (v) => set(() => picked = v),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(tr('Cancel')),
            ),
            if (picked != null)
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(tr('Add')),
              ),
          ],
        ),
      ),
    );
    if (ok == true && picked != null) {
      await store.api.post('/bots/$id/invite', {'server': picked});
      if (context.mounted) showSnack(context, 'Bot added');
    }
  } catch (e) {
    if (context.mounted) showSnack(context, errorText(e));
  }
}

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key, required this.path});
  final String path;

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  WebViewController? _controller;
  late final String _src;

  static bool get _nativeWebView =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  void initState() {
    super.initState();
    final uri = Uri.parse(widget.path);
    final query = Map<String, String>.from(uri.queryParameters)
      ..['embedded'] = 'true';
    _src = Uri.parse('$discoverUrl${relPath(uri.path)}')
        .replace(queryParameters: query)
        .toString();
    if (_nativeWebView) {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (req) {
              final u = Uri.parse(req.url);
              final seg = u.pathSegments;
              if (u.origin == discoverUrl &&
                  seg.length == 2 &&
                  (seg[0] == 'invite' || seg[0] == 'bot')) {
                _open(seg[0], seg[1]);
                return NavigationDecision.prevent;
              }
              if (u.origin != discoverUrl) {
                openUrl(req.url);
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            },
          ),
        )
        ..loadRequest(Uri.parse(_src));
    }
  }

  void _open(String kind, String id) {
    if (!mounted) return;
    context.goPath('/$kind/$id');
  }

  void _onMessage(Map<String, dynamic> m) {
    if (!mounted) return;
    switch (m['type']) {
      case 'path':
        var p = m['path'] as String;
        if (p.endsWith('?')) p = p.substring(0, p.length - 1);
        context.read<SettingsStore>().lastActivePath = p;
        context.go(context.href(p));
      case 'navigate':
        final u = Uri.tryParse(m['url'] as String? ?? '');
        final seg = u?.pathSegments ?? const [];
        if (seg.length >= 2 &&
            (seg[seg.length - 2] == 'invite' || seg[seg.length - 2] == 'bot')) {
          _open(seg[seg.length - 2], seg.last);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final embed = kIsWeb ? buildWebEmbed(_src, _onMessage) : null;
    return Column(
      children: [
        PageHeader(icon: Icon(Icons.explore), title: Text(tr('Discover'))),
        Expanded(
          child:
              embed ??
              (_controller != null
                  ? WebViewWidget(controller: _controller!)
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Wordmark(width: 240),
                          const SizedBox(height: 16),
                          Text(
                            tr(
                              'Find a community based on your hobbies or interests.',
                            ),
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            icon: const Icon(Icons.open_in_new),
                            onPressed: () => openUrl(
                              _src.replaceFirst(
                                'embedded=true',
                                'embedded=false',
                              ),
                            ),
                            label: const Text('Open Discover'),
                          ),
                        ],
                      ),
                    )),
        ),
      ],
    );
  }
}

class DevelopmentPage extends StatelessWidget {
  const DevelopmentPage({super.key});
  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    return Column(
      children: [
        const PageHeader(icon: Icon(Icons.build), title: Text('Development')),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Host: ${store.host ?? dawnchatHost}'),
              Text('API: ${store.api.baseUrl}'),
              Text('WS: ${store.api.config?.ws}'),
              Text('User: ${store.userId}'),
              Text(
                'Servers: ${store.servers.length}  Channels: ${store.channels.length}  Users: ${store.users.length}',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
