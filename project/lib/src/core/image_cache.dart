import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;

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

/// Size-accounted LRU store for downloaded bytes. Insertion order doubles as
/// recency order: [get] re-inserts the key so the oldest entry is always the
/// least recently used one.
class _ByteLru {
  _ByteLru({required this.limit, this.maxCount, this.onEvict});
  final int limit;
  final int? maxCount;
  final void Function(String key)? onEvict;
  final Map<String, Uint8List> map = {};
  int size = 0;

  Uint8List? get(String key) {
    final v = map.remove(key);
    if (v == null) return null;
    map[key] = v;
    return v;
  }

  void put(String key, Uint8List bytes) {
    final prev = map.remove(key);
    if (prev != null) size -= prev.length;
    map[key] = bytes;
    size += bytes.length;
    while (map.length > 1 &&
        (size > limit || (maxCount != null && map.length > maxCount!))) {
      final k = map.keys.first;
      size -= map.remove(k)!.length;
      onEvict?.call(k);
    }
  }

  /// Drops the oldest entries until [targetSize] bytes remain. Used by the
  /// janitor to release memory after a burst of image loads instead of
  /// sitting at the high-water mark.
  void trimTo(int targetSize) {
    while (size > targetSize && map.length > 1) {
      final k = map.keys.first;
      size -= map.remove(k)!.length;
      onEvict?.call(k);
    }
  }
}

final Map<String, Future<Uint8List>> _bytesInFlight = {};
final _bytesMemory = _ByteLru(limit: 48 * 1024 * 1024, maxCount: 2000);

/// Bytes for [url] from memory, disk or network; concurrent callers share one download.
Future<Uint8List> cachedBytes(String url) =>
    useDiskImageCache ? _diskCachedBytes(url) : _webCachedBytes(url);

Future<Uint8List> _diskCachedBytes(String url) {
  final hit = _bytesMemory.get(url);
  if (hit != null) return SynchronousFuture(hit);
  return _bytesInFlight[url] ??= _limited(() async {
    final file = await imageCacheManager.getSingleFile(url);
    final bytes = await file.readAsBytes();
    _bytesMemory.put(url, bytes);
    return bytes;
  }).whenComplete(() => _bytesInFlight.remove(url));
}

// ----- web -----
//
// The disk cache manager needs dart:io, so on web bytes live in memory only.
// The Future (not just the bytes) is cached per URL: every widget asking for
// the same image must share one stable Future, or FutureBuilder resubscribes
// on every rebuild.
final Map<String, Future<Uint8List>> _webFutures = {};
final Map<String, DateTime> _webFailedAt = {};
final _webBytes = _ByteLru(
  limit: 96 * 1024 * 1024,
  onEvict: (url) {
    _webFutures.remove(url);
    _webFailedAt.remove(url);
  },
);

Future<Uint8List> _webCachedBytes(String url) {
  final cached = _webFutures[url];
  if (cached != null) {
    final failedAt = _webFailedAt[url];
    // Keep failures briefly so rebuilds don't refetch in a loop, then allow
    // a retry. Timestamp-based (not a Timer) so tests see no pending timers.
    if (failedAt == null ||
        DateTime.now().difference(failedAt) < const Duration(seconds: 30)) {
      _webBytes.get(url); // LRU touch — hits return the Future, bypassing get().
      return cached;
    }
    _webFutures.remove(url);
    _webFailedAt.remove(url);
  }
  return _webFutures[url] = _limited(() async {
    final res = await http.get(Uri.parse(url));
    if (res.statusCode != 200) {
      throw Exception('Image request failed (${res.statusCode})');
    }
    final bytes = res.bodyBytes;
    _webFailedAt.remove(url);
    _webBytes.put(url, bytes);
    return bytes;
  }).catchError((Object e) {
    _webFailedAt[url] = DateTime.now();
    throw e;
  });
}

Future<void> _settled(Future<Uint8List> f) async {
  try {
    await f;
  } catch (_) {}
}

/// Warms the cache for many images at once.
Future<void> prefetchImages(Iterable<String> urls) async {
  final unique = urls.toSet().toList();
  if (!useDiskImageCache) {
    await Future.wait([for (final u in unique) _settled(_webCachedBytes(u))]);
    return;
  }
  await Future.wait([
    for (final u in unique)
      _limited(() async {
        try {
          await imageCacheManager.getSingleFile(u);
        } catch (_) {}
      }),
  ]);
}

/// Releases half of each byte cache's budget. Called periodically by
/// [startImageJanitor] and safe to invoke manually under memory pressure.
void collectGarbage() {
  _bytesMemory.trimTo(_bytesMemory.limit ~/ 2);
  _webBytes.trimTo(_webBytes.limit ~/ 2);
}

/// Trims the byte caches on a timer so memory doesn't stay at the high-water
/// mark after bursts of image loads.
void startImageJanitor() {
  Timer.periodic(const Duration(minutes: 2), (_) => collectGarbage());
}
