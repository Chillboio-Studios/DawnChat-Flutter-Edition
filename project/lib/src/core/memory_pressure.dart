// Platform memory-pressure probe. On VM platforms this polls the process
// RSS; on web it reads `performance.memory` where available (Chromium).
export 'memory_pressure_stub.dart'
    if (dart.library.io) 'memory_pressure_io.dart'
    if (dart.library.js_interop) 'memory_pressure_web.dart';
