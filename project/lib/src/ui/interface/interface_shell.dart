import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/client_store.dart';
import '../../router.dart';
import '../../state/settings_store.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../voice/voice_manager.dart';
import '../voice/voice_ui.dart';
import '../widgets.dart';
import 'server_rail.dart';
import 'sidebars.dart';
import '../../core/i18n.dart';
import '../modals/app_dialog.dart';

/// Parsed in-app location used to pick sidebars.
class NavTarget {
  NavTarget(this.serverId, this.channelId, this.discover);
  final String? serverId;
  final String? channelId;
  final bool discover;

  static NavTarget parse(String location, ClientStore store) {
    final seg = relPath(location)
        .split('/')
        .where((e) => e.isNotEmpty)
        .toList();
    String? server, channel;
    var discover = false;
    for (var i = 0; i < seg.length; i++) {
      if (seg[i] == 'server' && i + 1 < seg.length) server = seg[i + 1];
      if (seg[i] == 'channel' && i + 1 < seg.length) channel = seg[i + 1];
      if (seg[i] == 'discover') discover = true;
    }
    if (server == null && channel != null) {
      server = store.channels[channel]?['server'] as String?;
    }
    return NavTarget(server, channel, discover);
  }
}

class InterfaceShell extends StatefulWidget {
  const InterfaceShell({
    super.key,
    required this.location,
    required this.child,
  });
  final String location;
  final Widget child;

  @override
  State<InterfaceShell> createState() => _InterfaceShellState();
}

class _InterfaceShellState extends State<InterfaceShell> {
  final _scaffold = GlobalKey<ScaffoldState>();
  late final VoiceManager _voice;

  @override
  void initState() {
    super.initState();
    _voice = context.read<VoiceManager>();
    _voice.lastError.addListener(_onVoiceError);
  }

  @override
  void dispose() {
    _voice.lastError.removeListener(_onVoiceError);
    super.dispose();
  }

  void _onVoiceError() {
    final e = _voice.lastError.value;
    if (e != null && mounted) showSnack(context, e);
  }

  /// The change-set instance already shown — the web client only shows the
  /// policy dialog once per session per set of changes.
  List<Json>? _shownPolicyChanges;

  Future<void> _showPolicyChange(ClientStore store) async {
    final changes = store.policyChanges;
    if (changes == null ||
        changes.isEmpty ||
        identical(changes, _shownPolicyChanges)) {
      return;
    }
    _shownPolicyChanges = changes;
    var confirm = false;
    await showAppDialog<void>(
      context,
      title: tr('Review policy changes'),
      content: StatefulBuilder(
        builder: (c, set) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(
                'Click on the items below to learn more about different changes!',
              ),
            ),
            const SizedBox(height: Gap.md),
            for (final change in changes)
              InkWell(
                onTap: () => openUrl(change['url'] as String? ?? ''),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              change['description'] as String? ?? '',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (change['effective_time'] != null)
                              Text(
                                'Effective ${change['effective_time']}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.cs.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const Icon(Icons.open_in_new, size: 18),
                    ],
                  ),
                ),
              ),
            CheckboxListTile(
              value: confirm,
              onChanged: (v) => set(() => confirm = v ?? false),
              title: Text(tr("I've read and reviewed the changes.")),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
      actions: [
        DlgAction(tr('Close')),
        DlgAction(
          tr('Acknowledge'),
          enabled: confirm,
          onPressed: () async {
            await store.acknowledgePolicies();
            return null;
          },
        ),
      ],
    );
  }

  @override
  void didUpdateWidget(InterfaceShell old) {
    super.didUpdateWidget(old);
    if (old.location != widget.location) {
      _trackPath();
      _scaffold.currentState?.closeDrawer();
    }
  }

  void _trackPath() {
    final s = context.read<SettingsStore>();
    final rel = relPath(widget.location);
    // Settings notify listeners, which is illegal while the tree is building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      s.lastActivePath = rel;
      final m = RegExp(r'^/server/([^/]+)').firstMatch(rel);
      if (m != null) s.setRaw('layout.server.${m.group(1)}', rel);
      if (rel.startsWith('/discover')) s.setRaw('layout.discover', rel);
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final cs = context.cs;
    final size = MediaQuery.sizeOf(context);
    final sc = screenClassOf(size);
    final target = NavTarget.parse(widget.location, store);

    if (store.authState != AuthState.loggedIn || !store.ready) {
      return Scaffold(
        backgroundColor: cs.surfaceContainerHigh,
        body: store.connection == LinkState.offline
            ? _Offline(onRetry: store.init)
            : const LoadingScreen(),
      );
    }

    final disconnected = store.connection != LinkState.connected;
    final sidebar = SidebarPanel(target: target);
    final rail = ServerRail(target: target);
    final content = VoiceOverlay(
      currentChannelId: target.channelId,
      child: widget.child,
    );

    // Policy change review — port of the web client's `PolicyChangeModal`.
    // The server pushes `PolicyChange` events; we show the dialog once per
    // pending set and acknowledge on accept.
    if (store.policyChanges != null && store.policyChanges!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showPolicyChange(store);
      });
    }

    if (sc == ScreenClass.phone) {
      final onHome =
          relPath(widget.location) == '/app' || relPath(widget.location) == '/';
      return Scaffold(
        key: _scaffold,
        backgroundColor: cs.surfaceContainerHigh,
        drawer: Drawer(
          width: size.width * 0.92,
          backgroundColor: cs.surfaceContainerHigh,
          child: SafeArea(
            child: Row(
              children: [
                rail,
                Expanded(child: sidebar),
              ],
            ),
          ),
        ),
        drawerEnableOpenDragGesture: true,
        body: SafeArea(
          child: onHome && target.serverId == null
              ? Row(
                  children: [
                    rail,
                    Expanded(child: sidebar),
                  ],
                )
              : Column(
                  children: [
                    Expanded(
                      child: _PhoneContent(scaffold: _scaffold, child: content),
                    ),
                  ],
                ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: disconnected
          ? cs.primaryContainer
          : cs.surfaceContainerHigh,
      body: SafeArea(
        child: Column(
          children: [
            if (disconnected)
              Container(
                width: double.infinity,
                color: cs.primaryContainer,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  store.connection == LinkState.offline
                      ? 'You are offline'
                      : 'Reconnecting…',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: cs.onPrimaryContainer,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Expanded(
              child: Row(
                children: [
                  rail,
                  if (!target.discover)
                    SizedBox(width: Layout.channelSidebarWidth, child: sidebar),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLow,
                        borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(Radius_.lg),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: content,
                    ),
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

class _PhoneContent extends StatelessWidget {
  const _PhoneContent({required this.scaffold, required this.child});
  final GlobalKey<ScaffoldState> scaffold;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Container(color: context.cs.surfaceContainerLow, child: child);
}

class _Offline extends StatelessWidget {
  const _Offline({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Wordmark(width: 140),
        const SizedBox(height: 24),
        const Text("Can't reach the server."),
        const SizedBox(height: 12),
        FilledButton(onPressed: onRetry, child: Text(tr('Try again'))),
      ],
    ),
  );
}
