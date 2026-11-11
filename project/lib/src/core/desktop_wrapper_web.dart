import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// The legacy DawnChat-For-DESKTOP Electron wrapper loads the web client in
/// a BrowserWindow whose preload script injects `window.native` and
/// `window.desktopConfig` via contextBridge, and whose user agent contains
/// "Electron". Either signal means this is the old wrapper.
bool isLegacyDesktopWrapper() {
  try {
    final w = web.window as JSObject;
    if (w.has('native') || w.has('desktopConfig')) return true;
  } catch (_) {}
  return web.window.navigator.userAgent.contains('Electron');
}
