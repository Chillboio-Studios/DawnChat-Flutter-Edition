import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:pasteboard/pasteboard.dart';

const usesBrowserPasteEvents = false;

Future<({Uint8List bytes, String mime, String name})?>
readClipboardImage() async {
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

VoidCallback listenClipboardImages({
  required bool Function() enabled,
  required void Function(Uint8List bytes, String mime, String name) onImage,
  required void Function(Object error, StackTrace stack) onError,
}) => () {};
