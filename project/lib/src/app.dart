import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'api/client_store.dart';
import 'core/desktop_wrapper.dart';
import 'core/i18n.dart';
import 'core/links.dart';
import 'desktop/desktop.dart';
import 'push/push_service.dart';
import 'router.dart';
import 'state/settings_store.dart';
import 'state/draft_store.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';
import 'ui/widgets.dart';
import 'voice/voice_manager.dart';

class DawnChatApp extends StatefulWidget {
  const DawnChatApp({super.key, required this.settings, required this.store});
  final SettingsStore settings;
  final ClientStore store;

  @override
  State<DawnChatApp> createState() => _DawnChatAppState();
}

class _DawnChatAppState extends State<DawnChatApp> with WidgetsBindingObserver {
  late final _router = buildRouter(widget.store, widget.settings);
  late final _sounds = SoundService(widget.settings);
  late final _voice = VoiceManager(widget.store, widget.settings, _sounds);
  late final _push = PushService(widget.store, widget.settings);
  final _drafts = DraftStore();

  /// True when running inside the legacy Electron desktop wrapper — those
  /// users get the "outdated" screen instead of the app.
  final bool _legacyWrapper = isLegacyDesktopWrapper();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.settings.addListener(_syncLanguage);
    widget.store.init();
    _push.sounds = _sounds;
    _push.init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _push.appInForeground = state == AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    widget.settings.removeListener(_syncLanguage);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _syncLanguage() {
    if (widget.settings.lang != I18n.code) I18n.load(widget.settings.lang);
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.settings),
        ChangeNotifierProvider.value(value: widget.store),
        Provider.value(value: _sounds),
        ChangeNotifierProvider.value(value: _voice),
        ChangeNotifierProvider.value(value: _push),
        ChangeNotifierProvider.value(value: _drafts),
      ],
      child: Consumer<SettingsStore>(
        builder: (context, s, _) {
          final platform = MediaQuery.platformBrightnessOf(context);
          final theme = buildTheme(s, platform);
          final rtl = appLanguageIsRtl(s.lang);
          if (_legacyWrapper) {
            return MaterialApp(
              title: 'DawnChat',
              debugShowCheckedModeBanner: false,
              theme: theme,
              home: const _LegacyWrapperScreen(),
            );
          }
          return ValueListenableBuilder<int>(
            valueListenable: I18n.revision,
            builder: (context, rev, _) => MaterialApp.router(
              key: ValueKey(rev),
              title: 'DawnChat',
              debugShowCheckedModeBanner: false,
              theme: theme,
              routerConfig: _router,
              builder: (context, child) => Directionality(
                textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                child: Shortcuts(
                  shortcuts: const {
                    SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
                  },
                  child: Actions(
                    actions: {
                      DismissIntent: CallbackAction<DismissIntent>(
                        onInvoke: (_) {
                          final nav = Navigator.maybeOf(context);
                          nav?.maybePop();
                          return null;
                        },
                      ),
                    },
                    child: Titlebar(child: child ?? const SizedBox.shrink()),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

bool appLanguageIsRtl(String code) =>
    const {'ar', 'fa', 'ckb', 'ur'}.contains(code);

/// Shown instead of the app when running inside the legacy Electron
/// desktop wrapper — those installs must be replaced by the Flutter build.
class _LegacyWrapperScreen extends StatelessWidget {
  const _LegacyWrapperScreen();

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(Gap.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Wordmark(width: 180),
                const SizedBox(height: Gap.xl),
                Text(
                  tr('DawnChat is outdated!'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: Gap.md),
                Text(
                  tr(
                    'Please uninstall the current version of DawnChat and download the latest build below.',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: Gap.xl),
                FilledButton.icon(
                  onPressed: () => openUrl(desktopDownloadUrl),
                  icon: const Icon(Icons.download_outlined),
                  label: Text(tr('Download latest build')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
