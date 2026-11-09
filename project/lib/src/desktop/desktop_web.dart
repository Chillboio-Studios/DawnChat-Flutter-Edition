import 'package:flutter/widgets.dart';

import '../state/settings_store.dart';

bool get isDesktop => false;

class DesktopIntegration {
  static Future<void> init(
    SettingsStore settings, {
    required bool launchedAtStartup,
  }) async {}
}

class Titlebar extends StatelessWidget {
  const Titlebar({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
