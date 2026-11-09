import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

final _registered = <String>{};

/// Plain sandboxed iframe for third-party embeds (YouTube, Spotify, ...).
Widget? buildPlainIframe(String src) {
  final viewType = 'iframe-${src.hashCode}';
  if (_registered.add(viewType)) {
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int id) {
      return web.HTMLIFrameElement()
        ..src = src
        ..allowFullscreen = true
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';
    });
  }
  return HtmlElementView(viewType: viewType);
}

/// Embeds Discover in an iframe and bridges its postMessage protocol.
Widget? buildWebEmbed(String src, void Function(Map<String, dynamic> message) onMessage) {
  final viewType = 'discover-${src.hashCode}';
  if (_registered.add(viewType)) {
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int id) {
      final iframe = web.HTMLIFrameElement()
        ..src = src
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';
      web.window.addEventListener(
        'message',
        ((web.MessageEvent e) {
          if (!web.window.location.origin.isNotEmpty) return;
          try {
            final data = e.data;
            if (data == null || !data.isA<JSString>()) return;
            final msg = jsonDecode((data as JSString).toDart) as Map<String, dynamic>;
            if (msg['source'] != 'discover') return;
            if (msg['type'] == 'init') {
              iframe.contentWindow?.postMessage(
                jsonEncode({'source': 'revolt', 'type': 'theme', 'theme': {}}).toJS,
                '*'.toJS,
              );
            }
            onMessage(msg);
          } catch (_) {}
        }).toJS,
      );
      return iframe;
    });
  }
  return HtmlElementView(viewType: viewType);
}
