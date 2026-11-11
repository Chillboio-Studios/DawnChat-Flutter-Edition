import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'api/client_store.dart';
import 'state/settings_store.dart';
import 'ui/admin/admin_page.dart';
import 'ui/auth/auth_page.dart';
import 'ui/auth/flows.dart';
import 'ui/interface/channel_page.dart';
import 'ui/interface/home_page.dart';
import 'ui/interface/interface_shell.dart';
import 'ui/interface/redirects.dart';
import 'ui/widgets.dart';

/// Prefixes in-app paths with `/i/:host` when connected to a non-default instance.
extension HrefX on BuildContext {
  String href(String path) {
    final host = read<ClientStore>().host;
    return host == null ? path : '/i/$host$path';
  }

  void goPath(String path) => GoRouter.of(this).go(href(path));
  void pushPath(String path) => GoRouter.of(this).push(href(path));

  /// Absolute shareable URL for an in-app path.
  String fullHref(String path) {
    final origin = kIsWeb ? Uri.base.origin : 'https://app.dawn-chat.com';
    return '$origin${href(path)}';
  }
}

String relPath(String path) =>
    path.replaceFirst(RegExp(r'^/i/[^/]+'), '').isEmpty
    ? '/'
    : path.replaceFirst(RegExp(r'^/i/[^/]+'), '');

GoRouter buildRouter(ClientStore store, SettingsStore settings) {
  List<RouteBase> tree(bool abs) {
    String p(String s) => abs ? '/$s' : s;

    return [
      ShellRoute(
        builder: (c, s, child) => AuthPage(child: child),
        routes: [
          GoRoute(
            path: p('delete/:token'),
            builder: (c, s) =>
                DeleteAccountFlow(token: s.pathParameters['token']!),
          ),
          GoRoute(
            path: p('login'),
            redirect: (c, s) =>
                s.uri.path.endsWith('/login') ? '${s.uri.path}/auth' : null,
            builder: (c, s) => const SizedBox.shrink(),
            routes: [
              GoRoute(
                path: 'delete/:token',
                builder: (c, s) =>
                    DeleteAccountFlow(token: s.pathParameters['token']!),
              ),
              GoRoute(path: 'check', builder: (c, s) => const FlowCheck()),
              GoRoute(
                path: 'create',
                builder: (c, s) => FlowCreate(code: null),
              ),
              GoRoute(
                path: 'create/:code',
                builder: (c, s) => FlowCreate(code: s.pathParameters['code']),
              ),
              GoRoute(path: 'auth', builder: (c, s) => const FlowLogin()),
              GoRoute(path: 'token', builder: (c, s) => const FlowToken()),
              GoRoute(path: 'resend', builder: (c, s) => const FlowResend()),
              GoRoute(path: 'reset', builder: (c, s) => const FlowReset()),
              GoRoute(
                path: 'verify/:token',
                builder: (c, s) =>
                    FlowVerify(token: s.pathParameters['token']!),
              ),
              GoRoute(
                path: 'reset/:token',
                builder: (c, s) =>
                    FlowConfirmReset(token: s.pathParameters['token']!),
              ),
            ],
          ),
        ],
      ),
      ShellRoute(
        builder: (c, s, child) =>
            InterfaceShell(location: s.uri.path, child: child),
        routes: [
          GoRoute(path: p('pwa'), builder: (c, s) => const PwaRedirect()),
          GoRoute(path: p('dev'), builder: (c, s) => const DevelopmentPage()),
          GoRoute(
            path: p('discover'),
            builder: (c, s) => DiscoverPage(path: s.uri.toString()),
          ),
          GoRoute(
            path: p('discover/:rest(.*)'),
            builder: (c, s) => DiscoverPage(path: s.uri.toString()),
          ),
          GoRoute(
            path: p('settings'),
            builder: (c, s) => const SettingsRedirect(),
          ),
          GoRoute(
            path: p('invite/:code'),
            builder: (c, s) => InviteRedirect(code: s.pathParameters['code']!),
          ),
          GoRoute(
            path: p('bot/:code'),
            builder: (c, s) => BotRedirect(code: s.pathParameters['code']!),
          ),
          GoRoute(path: p('friends'), builder: (c, s) => const FriendsPage()),
          GoRoute(
            path: p('server/:server'),
            builder: (c, s) =>
                ServerHome(serverId: s.pathParameters['server']!),
            routes: [
              GoRoute(
                path: 'channel/:channel',
                builder: (c, s) => ChannelPage(
                  key: ValueKey(s.pathParameters['channel']),
                  channelId: s.pathParameters['channel']!,
                ),
              ),
              GoRoute(
                path: 'channel/:channel/:message',
                builder: (c, s) => ChannelPage(
                  key: ValueKey(s.pathParameters['channel']),
                  channelId: s.pathParameters['channel']!,
                  messageId: s.pathParameters['message'],
                ),
              ),
              // Legacy wildcard — the web client matches any subpath here.
              GoRoute(
                path: ':rest(.*)',
                redirect: (c, s) =>
                    '${s.pathParameters['host'] != null ? '/i/${s.pathParameters['host']}' : ''}'
                    '/server/${s.pathParameters['server']}',
              ),
            ],
          ),
          GoRoute(
            path: p('channel/:channel'),
            builder: (c, s) => ChannelPage(
              key: ValueKey(s.pathParameters['channel']),
              channelId: s.pathParameters['channel']!,
            ),
          ),
          GoRoute(
            path: p('channel/:channel/:message'),
            builder: (c, s) => ChannelPage(
              key: ValueKey(s.pathParameters['channel']),
              channelId: s.pathParameters['channel']!,
              messageId: s.pathParameters['message'],
            ),
          ),
          // Legacy wildcard — extra segments still open the channel.
          GoRoute(
            path: p('channel/:channel/:rest(.*)'),
            redirect: (c, s) =>
                '${s.pathParameters['host'] != null ? '/i/${s.pathParameters['host']}' : ''}'
                '/channel/${s.pathParameters['channel']}',
          ),
          GoRoute(path: p('admin'), builder: (c, s) => const AdminPage()),
          GoRoute(path: p('app'), builder: (c, s) => const HomePage()),
          if (abs) GoRoute(path: '/', builder: (c, s) => const HomePage()),
        ],
      ),
    ];
  }

  return GoRouter(
    refreshListenable: store,
    debugLogDiagnostics: false,
    errorBuilder: (c, s) => const NotFoundPage(),
    redirect: (context, state) {
      final path = relPath(state.uri.path);
      final inAuth = path.startsWith('/login') || path.startsWith('/delete');
      final hostPrefix = RegExp(r'^/i/[^/]+').stringMatch(state.uri.path) ?? '';

      if (state.uri.path == hostPrefix && hostPrefix.isNotEmpty) {
        return '$hostPrefix/app';
      }
      if (store.authState == AuthState.unknown) return null;

      if (store.authState == AuthState.loggedOut && !inAuth) {
        settings.nextPath = path;
        return '$hostPrefix/login/auth';
      }
      if (path.startsWith('/login/') && !_knownLogin(path)) {
        return '$hostPrefix/login/auth';
      }
      return null;
    },
    routes: [
      ShellRoute(
        builder: (c, s, child) =>
            InstanceScope(host: s.pathParameters['host'], child: child),
        routes: [
          ...tree(true),
          GoRoute(
            path: '/i/:host',
            redirect: (c, s) =>
                s.uri.path.replaceAll(RegExp(r'/+$'), '') ==
                    '/i/${s.pathParameters['host']}'
                ? '/i/${s.pathParameters['host']}/app'
                : null,
            builder: (c, s) => const SizedBox.shrink(),
            routes: tree(false),
          ),
        ],
      ),
    ],
  );
}

bool _knownLogin(String path) {
  final seg = path.split('/').where((e) => e.isNotEmpty).toList();
  if (seg.length < 2) return true;
  const known = {
    'check',
    'create',
    'auth',
    'token',
    'resend',
    'reset',
    'verify',
    'delete',
  };
  return known.contains(seg[1]);
}

/// Switches the active instance to the `/i/:host` path segment and waits until it is ready.
class InstanceScope extends StatefulWidget {
  const InstanceScope({super.key, required this.host, required this.child});
  final String? host;
  final Widget child;

  @override
  State<InstanceScope> createState() => _InstanceScopeState();
}

class _InstanceScopeState extends State<InstanceScope> {
  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(InstanceScope old) {
    super.didUpdateWidget(old);
    if (old.host != widget.host) _sync();
  }

  void _sync() {
    final h = widget.host;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final store = context.read<ClientStore>();
      final norm = h == null ? null : (h == 'chat.dawn-chat.com' ? null : h);
      if (store.host != norm) store.switchHost(norm);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ClientStore>().authState;
    if (state == AuthState.unknown) return const LoadingScreen();
    return widget.child;
  }
}
