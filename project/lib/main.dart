import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:media_kit/media_kit.dart';

import 'src/api/client_store.dart';
import 'src/app.dart';
import 'src/core/i18n.dart';
import 'src/desktop/desktop.dart';
import 'src/rust/frb_generated.dart';
import 'src/state/settings_store.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  PaintingBinding.instance.imageCache
    ..maximumSize = 2000
    ..maximumSizeBytes = 400 << 20;
  if (kIsWeb) usePathUrlStrategy();
  if (!kIsWeb) await RustLib.init();
  final settings = await SettingsStore.load();
  await I18n.load(settings.lang);
  if (isDesktop) {
    launchAtStartup.setup(
      appName: 'DawnChat',
      appPath: Platform.resolvedExecutable,
      args: const ['--autostart'],
    );
    await DesktopIntegration.init(
      settings,
      launchedAtStartup: args.contains('--autostart'),
    );
  }
  runApp(DawnChatApp(settings: settings, store: ClientStore(settings)));
}
