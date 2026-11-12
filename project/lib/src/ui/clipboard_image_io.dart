import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mime/mime.dart';
import 'package:pasteboard/pasteboard.dart';

const usesBrowserPasteEvents = false;

/// Native clipboard reader (Android) — handles clip items the pasteboard
/// plugin misses: intents, text URIs and multi-item clips.
const _channel = MethodChannel('dawnchat/clipboard');

Future<({Uint8List bytes, String mime, String name})?>
readClipboardImage() async {
  if (defaultTargetPlatform == TargetPlatform.android) {
    try {
      final res = await _channel.invokeMethod<Map>('readImage');
      if (res != null) {
        final bytes = res['bytes'] as Uint8List?;
        final mime = res['mime'] as String? ?? '';
        if (bytes != null && bytes.isNotEmpty && mime.startsWith('image/')) {
          return (
            bytes: bytes,
            mime: mime,
            name:
                res['name'] as String? ??
                'clipboard.${extensionFromMime(mime)}',
          );
        }
      }
    } catch (_) {}
  }
  final bytes = await Pasteboard.image;
  if (bytes == null || bytes.isEmpty) return null;
  final mime = lookupMimeType('', headerBytes: bytes);
  if (mime == null || !mime.startsWith('image/')) {
    throw const FormatException('Unsupported clipboard image format');
  }
  return (
    bytes: bytes,
    mime: mime,
    name: 'clipboard.${extensionFromMime(mime)}',
  );
}

/// Non-image files on the clipboard (Android only for now — other
/// platforms fall back to the file picker).
Future<List<({String name, Uint8List bytes, String? mime})>>
readClipboardFiles() async {
  if (defaultTargetPlatform != TargetPlatform.android) return const [];
  try {
    final res = await _channel.invokeMethod<List>('readFiles');
    if (res == null) return const [];
    final out = <({String name, Uint8List bytes, String? mime})>[];
    for (final e in res) {
      final m = (e as Map).cast<String, dynamic>();
      final path = m['path'] as String?;
      if (path == null) continue;
      final f = File(path);
      if (!f.existsSync()) continue;
      out.add((
        name: m['name'] as String? ?? f.uri.pathSegments.last,
        bytes: await f.readAsBytes(),
        mime: m['mime'] as String? ?? 'application/octet-stream',
      ));
      // Cache copies are single-use — the draft store owns the bytes now.
      try {
        await f.delete();
      } catch (_) {}
    }
    return out;
  } catch (_) {
    return const [];
  }
}

VoidCallback listenClipboardImages({
  required bool Function() enabled,
  required void Function(Uint8List bytes, String mime, String name) onImage,
  required void Function(Object error, StackTrace stack) onError,
}) => () {};
