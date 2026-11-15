import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/painting.dart' hide Size;

import 'image_cache.dart';

/// Resident-set size in bytes, or null when the platform can't report it.
int? _residentBytes() {
  if (Platform.isLinux) return _linuxRss();
  if (Platform.isWindows) return _windowsRss();
  if (Platform.isMacOS) return _macosRss();
  return null;
}

int? _linuxRss() {
  try {
    final status = File('/proc/self/status').readAsStringSync();
    final m = RegExp(r'VmRSS:\s+(\d+)\s*kB').firstMatch(status);
    return m == null ? null : int.parse(m.group(1)!) * 1024;
  } catch (_) {
    return null;
  }
}

final class _ProcessMemoryCounters extends Struct {
  @Uint32() external int cb;
  @Uint32() external int pageFaultCount;
  @Size() external int peakWorkingSetSize;
  @Size() external int workingSetSize;
  @Size() external int quotaPeakPagedPoolUsage;
  @Size() external int quotaPagedPoolUsage;
  @Size() external int quotaPeakNonPagedPoolUsage;
  @Size() external int quotaNonPagedPoolUsage;
  @Size() external int pagefileUsage;
  @Size() external int peakPagefileUsage;
}

final _k32GetProcessMemoryInfo = DynamicLibrary.open('kernel32.dll')
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<_ProcessMemoryCounters>, Uint32),
      int Function(int, Pointer<_ProcessMemoryCounters>, int)>(
      'K32GetProcessMemoryInfo',
    );

int? _windowsRss() {
  final c = calloc<_ProcessMemoryCounters>();
  try {
    // -1 is the GetCurrentProcess() pseudo-handle.
    final ok = _k32GetProcessMemoryInfo(-1, c, sizeOf<_ProcessMemoryCounters>());
    return ok == 0 ? null : c.ref.workingSetSize;
  } catch (_) {
    return null;
  } finally {
    calloc.free(c);
  }
}

final _procPidRusage = DynamicLibrary.open('/usr/lib/libproc.dylib')
    .lookupFunction<
      Int32 Function(Int32, Int32, Pointer<Uint8>),
      int Function(int, int, Pointer<Uint8>)>('proc_pid_rusage');

int? _macosRss() {
  // rusage_info_v4 is ~176 bytes; a 256-byte buffer is safely oversized.
  // Layout: uuid[16], then u64 fields — phys_footprint sits at byte 72
  // (Uint64 index 9), which is the metric macOS jetsam accounts on.
  final buf = calloc<Uint8>(256);
  try {
    const rusageInfoV4 = 4;
    final ok = _procPidRusage(pid, rusageInfoV4, buf);
    if (ok != 0) return null;
    return buf.cast<Uint64>()[9];
  } catch (_) {
    return null;
  } finally {
    calloc.free(buf);
  }
}

/// Soft/hard RSS thresholds. Above soft: trim the byte caches. If pressure
/// persists past hard on the next poll, also drop decoded images.
const _softLimit = 768 << 20;
const _hardLimit = 1 << 30;

/// Polls process memory every 60s and escalates [collectGarbage] when RSS
/// climbs. Complements `didHaveMemoryPressure`, which only fires on
/// Android/iOS.
void startMemoryPressureMonitor() {
  Timer.periodic(const Duration(seconds: 60), (_) {
    final rss = _residentBytes();
    if (rss == null) return;
    if (rss > _hardLimit) {
      collectGarbage();
      PaintingBinding.instance.imageCache.clear();
    } else if (rss > _softLimit) {
      collectGarbage();
    }
  });
}
