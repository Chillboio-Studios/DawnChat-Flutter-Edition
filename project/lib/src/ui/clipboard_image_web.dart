import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:web/web.dart' as web;

const usesBrowserPasteEvents = true;

Future<({Uint8List bytes, String mime, String name})?>
readClipboardImage() async {
  final items = await web.window.navigator.clipboard.read().toDart;
  for (final item in items.toDart) {
    for (final type in item.types.toDart) {
      final mime = type.toDart;
      if (!mime.startsWith('image/')) continue;
      final blob = await item.getType(mime).toDart;
      final buffer = await blob.arrayBuffer().toDart;
      return (
        bytes: buffer.toDart.asUint8List(),
        mime: mime,
        name: 'clipboard.${extensionFromMime(mime)}',
      );
    }
  }
  return null;
}

VoidCallback listenClipboardImages({
  required bool Function() enabled,
  required void Function(Uint8List bytes, String mime, String name) onImage,
  required void Function(Object error, StackTrace stack) onError,
}) {
  final listener = ((web.ClipboardEvent event) {
    if (!enabled()) return;
    final items = event.clipboardData?.items;
    if (items == null) return;
    final images = <web.File>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item.kind != 'file' || !item.type.startsWith('image/')) continue;
      final file = item.getAsFile();
      if (file != null) images.add(file);
    }
    if (images.isEmpty) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    unawaited(() async {
      try {
        for (final image in images) {
          final buffer = await image.arrayBuffer().toDart;
          onImage(buffer.toDart.asUint8List(), image.type, image.name);
        }
      } catch (error, stack) {
        onError(error, stack);
      }
    }());
  }).toJS;
  web.document.addEventListener('paste', listener, true.toJS);
  return () => web.document.removeEventListener('paste', listener, true.toJS);
}
