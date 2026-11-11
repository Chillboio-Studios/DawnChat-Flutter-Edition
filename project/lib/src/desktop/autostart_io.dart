import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:win32_registry/win32_registry.dart';

/// Launch-at-login without a plugin:
/// - Windows: `HKCU\...\Run` value pointing at the executable with `--autostart`
/// - macOS: `~/Library/LaunchAgents` plist
/// - Linux: `~/.config/autostart` `.desktop` file
const _appName = 'DawnChat';
const _bundleId = 'com.chillboiostudios.dawnchat';
const _runKeyPath = r'Software\Microsoft\Windows\CurrentVersion\Run';

String get _launchCommand {
  final exe = Platform.resolvedExecutable;
  return Platform.isWindows ? '"$exe" --autostart' : '$exe --autostart';
}

Future<bool> autostartIsEnabled() async {
  if (kIsWeb) return false;
  try {
    if (Platform.isWindows) {
      final key = CURRENT_USER.open(_runKeyPath);
      try {
        return key.getString(_appName) != null;
      } finally {
        key.close();
      }
    }
    if (Platform.isMacOS) {
      return await File('$_home/Library/LaunchAgents/$_bundleId.plist')
          .exists();
    }
    if (Platform.isLinux) {
      return await File('$_home/.config/autostart/$_bundleId.desktop').exists();
    }
  } catch (e) {
    debugPrint('autostartIsEnabled failed: $e');
  }
  return false;
}

Future<void> autostartSetEnabled(bool enabled) async {
  if (kIsWeb) return;
  try {
    if (Platform.isWindows) {
      final key = CURRENT_USER.open(
        _runKeyPath,
        config: const RegistryOpenConfig(access: RegistryAccess.all),
      );
      try {
        if (enabled) {
          key.setValue(_appName, RegistryValue.string(_launchCommand));
        } else {
          key.removeValue(_appName);
        }
      } finally {
        key.close();
      }
      return;
    }
    if (Platform.isMacOS) {
      final file = File('$_home/Library/LaunchAgents/$_bundleId.plist');
      if (enabled) {
        await file.parent.create(recursive: true);
        await file.writeAsString('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$_bundleId</string>
	<key>ProgramArguments</key>
	<array>
		<string>${Platform.resolvedExecutable}</string>
		<string>--autostart</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
''');
      } else if (await file.exists()) {
        await file.delete();
      }
      return;
    }
    if (Platform.isLinux) {
      final file = File('$_home/.config/autostart/$_bundleId.desktop');
      if (enabled) {
        await file.parent.create(recursive: true);
        await file.writeAsString('''[Desktop Entry]
Type=Application
Name=$_appName
Comment=A User-First chat application
Exec=${Platform.resolvedExecutable} --autostart
Icon=$_appName
Terminal=false
X-GNOME-Autostart-enabled=true
''');
      } else if (await file.exists()) {
        await file.delete();
      }
    }
  } catch (e) {
    debugPrint('autostartSetEnabled failed: $e');
    rethrow;
  }
}

String get _home => Platform.environment['HOME'] ?? '';
