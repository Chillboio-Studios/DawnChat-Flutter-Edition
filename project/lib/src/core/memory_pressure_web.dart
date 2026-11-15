import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/painting.dart';
import 'package:web/web.dart' as web;

import 'image_cache.dart';

/// `performance.memory` is a non-standard Chromium API — absent on
/// Firefox/Safari, so every access is guarded.
(double, double)? _jsHeap() {
  try {
    final mem = web.window.performance.getProperty('memory'.toJS);
    if (mem == null || !mem.isA<JSObject>()) return null;
    final m = mem as JSObject;
    final usedAny = m.getProperty('usedJSHeapSize'.toJS);
    if (usedAny == null || !usedAny.isA<JSNumber>()) return null;
    final limitAny = m.getProperty('jsHeapSizeLimit'.toJS);
    final used = (usedAny as JSNumber).toDartDouble;
    final limit = limitAny != null && limitAny.isA<JSNumber>()
        ? (limitAny as JSNumber).toDartDouble
        : 0.0;
    return (used, limit);
  } catch (_) {
    return null;
  }
}

/// Polls the JS heap every 60s. Above 75% of the heap limit: trim the byte
/// caches. Above 90%: also drop decoded images.
void startMemoryPressureMonitor() {
  Timer.periodic(const Duration(seconds: 60), (_) {
    final heap = _jsHeap();
    if (heap == null) return;
    final (used, limit) = heap;
    if (limit <= 0) return;
    final ratio = used / limit;
    if (ratio > 0.9) {
      collectGarbage();
      PaintingBinding.instance.imageCache.clear();
    } else if (ratio > 0.75) {
      collectGarbage();
    }
  });
}
