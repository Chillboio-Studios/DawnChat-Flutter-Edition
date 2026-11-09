import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Disk cache for avatars, icons, emoji and embeds (not used on web, where the browser caches).
bool useDiskImageCache = !kIsWeb;
final CacheManager imageCacheManager = CacheManager(
  Config(
    'dawnchat_images',
    stalePeriod: const Duration(days: 30),
    maxNrOfCacheObjects: 4000,
  ),
);

const _maxConcurrentDownloads = 16;
int _active = 0;
final Queue<Completer<void>> _waiting = Queue();

Future<T> _limited<T>(Future<T> Function() job) async {
  if (_active >= _maxConcurrentDownloads) {
    final c = Completer<void>();
    _waiting.add(c);
    await c.future;
  }
  _active++;
  try {
    return await job();
  } finally {
    _active--;
    if (_waiting.isNotEmpty) _waiting.removeFirst().complete();
  }
}

final Map<String, Future<Uint8List>> _bytesInFlight = {};
final Map<String, Uint8List> _bytesMemory = {};

/// Bytes for [url] from memory, disk or network; concurrent callers share one download.
Future<Uint8List> cachedBytes(String url) {
  final hit = _bytesMemory[url];
  if (hit != null) return SynchronousFuture(hit);
  return _bytesInFlight[url] ??= _limited(() async {
    final file = await imageCacheManager.getSingleFile(url);
    final bytes = await file.readAsBytes();
    if (_bytesMemory.length > 600) _bytesMemory.remove(_bytesMemory.keys.first);
    _bytesMemory[url] = bytes;
    return bytes;
  }).whenComplete(() => _bytesInFlight.remove(url));
}

/// Warms the disk cache for many images at once.
Future<void> prefetchImages(Iterable<String> urls) async {
  if (!useDiskImageCache) return;
  final unique = urls.toSet().toList();
  await Future.wait([
    for (final u in unique)
      _limited(() async {
        try {
          await imageCacheManager.getSingleFile(u);
        } catch (_) {}
      }),
  ]);
}
