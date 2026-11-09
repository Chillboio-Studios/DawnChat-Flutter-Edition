import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'api/client_store.dart';
import 'core/i18n.dart';
import 'desktop/desktop.dart';
import 'push/push_service.dart';
import 'router.dart';
import 'state/settings_store.dart';
import 'state/draft_store.dart';
import 'theme/app_theme.dart';
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
