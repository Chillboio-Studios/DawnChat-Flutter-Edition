import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:media_kit/media_kit.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'src/api/client_store.dart';
import 'src/app.dart';
import 'src/core/i18n.dart';
import 'src/desktop/desktop.dart';
import 'src/rust/frb_generated.dart';
import 'src/state/settings_store.dart';

const _sentryDsn =
    'https://044161ed6b4b4257aeb35aa1973bfd9f@glitchtip.services.chillboiocloud.org/3';

Future<void> main(List<String> args) async {
  if (kReleaseMode) {
    await SentryFlutter.init(
      (options) => options
        ..dsn = _sentryDsn
        ..tracesSampleRate = 0.01
        ..enableAutoSessionTracking = false,
      appRunner: () => _run(args),
    );
    return;
  }
  await _run(args);
}

Future<void> _run(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  PaintingBinding.instance.imageCache
    ..maximumSize = 2000
    ..maximumSizeBytes = 400 << 20;
  if (kIsWeb) usePathUrlStrategy();
  // Native lib load and disk settings are independent — fetch both at once.
  final results = await Future.wait<Object?>([
    if (!kIsWeb) RustLib.init(),
    SettingsStore.load(),
  ]);
  final settings = results.last! as SettingsStore;
  // Language pack and desktop integration both only need settings.
  await Future.wait<void>([
    I18n.load(settings.lang),
    if (isDesktop)
      DesktopIntegration.init(
        settings,
        launchedAtStartup: args.contains('--autostart'),
      ),
  ]);
  runApp(DawnChatApp(settings: settings, store: ClientStore(settings)));
}
