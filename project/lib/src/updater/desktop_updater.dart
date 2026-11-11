import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Self-updater for the Flutter desktop builds. Polls the GitHub releases
/// feed for DawnChat-Flutter-Edition and installs the matching asset:
/// `dawnchat-windows.zip` on Windows, `DawnChat-*.AppImage` or
/// `dawnchat-linux.tar.gz` on Linux. macOS is excluded (App Store).
class DesktopUpdater {
  DesktopUpdater._();

  static const _repo = 'Chillboio-Studios/DawnChat-Flutter-Edition';
  static const _api = 'https://api.github.com/repos/$_repo/releases/latest';
  static const _page = 'https://github.com/$_repo/releases/latest';

  /// Whether this build can self-update. Disabled in debug/profile
  /// (dev) builds and on non-desktop/mobile/web platforms.
  static bool get isSupported =>
      !kIsWeb &&
      !kDebugMode &&
      !kProfileMode &&
      const bool.fromEnvironment('DAWNCHAT_DISABLE_UPDATER') == false &&
      (Platform.isWindows || Platform.isLinux);

  /// Latest release info, or null when up-to-date / unsupported / offline.
  static Future<ReleaseInfo?> check() async {
    if (!isSupported) return null;
    try {
      final res = await http
          .get(Uri.parse(_api), headers: {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'DawnChat-Desktop',
          })
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final tag = body['tag_name'] as String?;
      if (tag == null) return null;
      final info = await PackageInfo.fromPlatform();
      final latest = _versionOf(tag);
      final current = _versionOf(info.version);
      if (latest == null || current == null) return null;
      if (!_isNewer(latest, current)) return null;

      final assets = (body['assets'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      final asset = _pickAsset(assets);
      return ReleaseInfo(
        tag: tag,
        name: body['name'] as String? ?? tag,
        notes: body['body'] as String? ?? '',
        downloadUrl: asset?['browser_download_url'] as String?,
        assetName: asset?['name'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  static List<int>? _versionOf(String v) {
    final core = v.replaceFirst(RegExp(r'^[vV]'), '').split(RegExp(r'[-+]')).first;
    final parts = core.split('.').map(int.tryParse).toList();
    if (parts.isEmpty || parts.any((p) => p == null)) return null;
    while (parts.length < 3) {
      parts.add(0);
    }
    return parts.cast<int>();
  }

  static bool _isNewer(List<int> latest, List<int> current) {
    for (var i = 0; i < 3; i++) {
      if (latest[i] != current[i]) return latest[i] > current[i];
    }
    return false;
  }

  static Map<String, dynamic>? _pickAsset(List<Map<String, dynamic>> assets) {
    Map<String, dynamic>? find(String s) => assets
        .where((a) => (a['name'] as String? ?? '').toLowerCase().contains(s))
        .firstOrNull;
    if (Platform.isWindows) return find('windows');
    // Linux: prefer AppImage (single-file swap), else the tarball.
    return find('appimage') ?? find('linux');
  }

  /// Downloads [info]'s asset and installs it. [onProgress] gets 0..1.
  /// Returns true when the app should exit to let the installer finish.
  static Future<bool> install(
    ReleaseInfo info, {
    void Function(double)? onProgress,
  }) async {
    final url = info.downloadUrl;
    if (url == null) {
      await launchUrl(Uri.parse(_page), mode: LaunchMode.externalApplication);
      return false;
    }
    final tmp = await getTemporaryDirectory();
    final file = File('${tmp.path}${Platform.pathSeparator}${info.assetName}');
    final res = await http.Client().send(
      http.Request('GET', Uri.parse(url)),
    );
    final total = res.contentLength ?? 0;
    var received = 0;
    final sink = file.openWrite();
    await for (final chunk in res.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) onProgress?.call(received / total);
    }
    await sink.close();

    if (Platform.isWindows) {
      return _installWindows(file, tmp.path);
    }
    return _installLinux(file, info.assetName ?? '');
  }

  // ---------------- Windows ----------------

  static Future<bool> _installWindows(File zip, String workDir) async {
    final exe = Platform.resolvedExecutable;
    final installDir = File(exe).parent.parent.path; // bundle root
    final staging = '$installDir${Platform.pathSeparator}_update';

    final bytes = await zip.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final f in archive) {
      if (f.isFile) {
        final out = File('$staging${Platform.pathSeparator}${f.name}');
        await out.parent.create(recursive: true);
        await out.writeAsBytes(f.content as List<int>);
      }
    }

    // Helper batch: wait for this process, robocopy staging over the
    // install dir, relaunch, clean up.
    final bat = File('$workDir${Platform.pathSeparator}dawnchat-update.bat');
    await bat.writeAsString('''
@echo off
timeout /t 2 /nobreak >nul
robocopy "$staging" "$installDir" /MIR /NFL /NDL /NJH /NJS >nul
start "" "$installDir\\dawnchat.exe"
rmdir /s /q "$staging"
del "%~f0"
''');
    await Process.start(
      'cmd',
      ['/c', 'start', '', '/min', bat.path],
      mode: ProcessStartMode.detached,
    );
    return true;
  }

  // ---------------- Linux ----------------

  static Future<bool> _installLinux(File file, String assetName) async {
    final lower = assetName.toLowerCase();
    if (lower.contains('appimage')) {
      await Process.run('chmod', ['+x', file.path]);
      final appImage = Platform.environment['APPIMAGE'];
      if (appImage == null) {
        // Not running from an AppImage — can't hot-swap; open the page.
        await launchUrl(Uri.parse(_page), mode: LaunchMode.externalApplication);
        return false;
      }
      final old = '$appImage.old';
      await File(appImage).rename(old);
      await file.rename(appImage);
      await Process.run('chmod', ['+x', appImage]);
      await Process.start(appImage, const [], mode: ProcessStartMode.detached);
      return true;
    }

    // tar.gz bundle: extract to staging and swap directories.
    final bytes = await file.readAsBytes();
    final archive = TarDecoder().decodeBytes(
      GZipDecoder().decodeBytes(bytes),
    );
    final exe = Platform.resolvedExecutable;
    final installDir = File(exe).parent.path; // .../dawnchat
    final parent = File(installDir).parent.path;
    final staging = '$parent${Platform.pathSeparator}dawnchat-new';

    for (final f in archive) {
      if (!f.isFile) continue;
      // Strip leading "dawnchat/" component if present.
      var name = f.name;
      if (name.startsWith('dawnchat/')) name = name.substring(9);
      if (name.isEmpty) continue;
      final out = File('$staging${Platform.pathSeparator}$name');
      await out.parent.create(recursive: true);
      await out.writeAsBytes(f.content as List<int>);
    }

    final old = '$parent${Platform.pathSeparator}dawnchat-old';
    await File(installDir).rename(old);
    await Directory(staging).rename(installDir);
    final newExe = '$installDir${Platform.pathSeparator}${File(exe).uri.pathSegments.last}';
    await Process.run('chmod', ['-R', '+x', installDir]);
    await Process.start(newExe, const [], mode: ProcessStartMode.detached);
    return true;
  }
}

class ReleaseInfo {
  const ReleaseInfo({
    required this.tag,
    required this.name,
    required this.notes,
    required this.downloadUrl,
    required this.assetName,
  });
  final String tag;
  final String name;
  final String notes;
  final String? downloadUrl;
  final String? assetName;

  String get version => tag.replaceFirst(RegExp(r'^[vV]'), '');
}
