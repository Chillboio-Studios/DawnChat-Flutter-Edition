import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tray_manager/legacy.dart';
import 'package:window_manager/window_manager.dart';

import '../state/settings_store.dart';

bool get isDesktop =>
    !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

/// Window frame, tray and close-to-tray behaviour for the desktop apps.
class DesktopIntegration with WindowListener, TrayListener {
  DesktopIntegration._(this.settings);
  final SettingsStore settings;

  static Future<void> init(
    SettingsStore settings, {
    required bool launchedAtStartup,
  }) async {
    if (!isDesktop) return;
    await windowManager.ensureInitialized();
    final d = DesktopIntegration._(settings);

    final options = WindowOptions(
      size: const Size(1280, 800),
      minimumSize: const Size(360, 480),
      title: 'DawnChat',
      titleBarStyle: settings.customFrame
          ? TitleBarStyle.hidden
          : TitleBarStyle.normal,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      if (launchedAtStartup && settings.startMinimisedToTray) {
        await windowManager.hide();
      } else {
        await windowManager.show();
        await windowManager.focus();
      }
    });
    await windowManager.setPreventClose(true);
    windowManager.addListener(d);

    try {
      trayManager.addListener(d);
      await trayManager.setIcon(
        Platform.isWindows
            ? 'assets/branding/icon.ico'
            : 'assets/branding/android-chrome-192x192.png',
      );
      if (!Platform.isLinux) await trayManager.setToolTip('DawnChat');
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'show', label: 'Open DawnChat'),
            MenuItem.separator(),
            MenuItem(key: 'quit', label: 'Quit'),
          ],
        ),
      );
    } catch (e) {
      debugPrint('Tray unavailable: $e');
    }
    settings.addListener(d._onSettings);
  }

  bool? _lastFrame;
  void _onSettings() {
    final frame = settings.customFrame;
    if (_lastFrame == frame) return;
    _lastFrame = frame;
    windowManager.setTitleBarStyle(
      frame ? TitleBarStyle.hidden : TitleBarStyle.normal,
    );
  }

  @override
  void onWindowClose() async {
    if (settings.minimiseToTray) {
      await windowManager.hide();
    } else {
      await windowManager.setPreventClose(false);
      await windowManager.close();
    }
  }

  @override
  void onTrayIconMouseDown() => _show();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem item) async {
    if (item.key == 'show') {
      _show();
    } else if (item.key == 'quit') {
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    }
  }

  Future<void> _show() async {
    await windowManager.show();
    await windowManager.focus();
  }
}

/// Custom window titlebar shown when the desktop "Custom window frame" setting is on.
class Titlebar extends StatelessWidget {
  const Titlebar({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isDesktop) return child;
    final custom = context.select<SettingsStore, bool>((s) => s.customFrame);
    if (!custom) return child;
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Material(
          color: cs.surfaceContainerHigh,
          child: SizedBox(
            height: 32,
            child: Row(
              children: [
                Expanded(
                  child: DragToMoveArea(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'DawnChat',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                _Btn(Icons.remove, () => windowManager.minimize()),
                _Btn(
                  Icons.crop_square,
                  () async => (await windowManager.isMaximized())
                      ? windowManager.unmaximize()
                      : windowManager.maximize(),
                ),
                _Btn(Icons.close, () => windowManager.close(), danger: true),
              ],
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn(this.icon, this.onTap, {this.danger = false});
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      hoverColor: danger ? cs.error : cs.surfaceContainerHighest,
      onTap: onTap,
      child: SizedBox(
        width: 46,
        height: 32,
        child: Icon(icon, size: 16, color: cs.onSurfaceVariant),
      ),
    );
  }
}
