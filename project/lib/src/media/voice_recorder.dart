import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Voice message metadata parsed from a message's content JSON.
/// Same shape the Android app writes (`chat.stoat.VoiceMessage`).
class VoiceMessageMeta {
  const VoiceMessageMeta({required this.durationMs, required this.waveform});
  final int durationMs;
  final List<int> waveform;
}

const _voiceContentId = 'chat.stoat.VoiceMessage';

/// Returns voice-message metadata when [content] is a voice message
/// payload, mirroring the Android `parseVoiceMessageMetadata` validation.
VoiceMessageMeta? parseVoiceMessageMeta(String? content) {
  if (content == null || !content.startsWith('{')) return null;
  final Map m;
  try {
    final v = jsonDecode(content);
    if (v is! Map) return null;
    m = v;
  } catch (_) {
    return null;
  }
  if (m.keys.toSet() != {'x', 'y', 'z', 'w'}) return null;
  if (m['x'] != _voiceContentId) return null;
  if (m['y'] != 1) return null;
  final duration = m['z'];
  if (duration is! int ||
      duration < VoiceRecorder.minDurationMs ||
      duration > VoiceRecorder.maxDurationMs) {
    return null;
  }
  final w = m['w'];
  if (w is! List ||
      w.isEmpty ||
      w.length > VoiceRecorder.waveformSampleCount) {
    return null;
  }
  final samples = <int>[];
  for (final s in w) {
    if (s is! int || s < 0 || s > 255) return null;
    samples.add(s);
  }
  return VoiceMessageMeta(durationMs: duration, waveform: samples);
}

/// A finished voice recording ready to upload.
class VoiceRecording {
  const VoiceRecording({
    required this.bytes,
    required this.mimeType,
    required this.fileExtension,
    required this.durationMillis,
    required this.waveform,
  });

  final Uint8List bytes;
  final String mimeType;
  final String fileExtension;
  final int durationMillis;
  final List<int> waveform;

  String get fileName => 'voice_message_$durationMillis.$fileExtension';

  /// Message `content` payload — identical to Android's
  /// `Recording.toMessageContent()`.
  String get messageContent => jsonEncode({
    'x': _voiceContentId,
    'y': 1,
    'z': durationMillis,
    'w': waveform,
  });
}

/// Reduce amplitude readings to a normalised waveform — port of the
/// Android `buildWaveform` (64 buckets, sqrt scaling).
List<int> buildVoiceWaveform(
  List<int> amplitudes, {
  int sampleCount = VoiceRecorder.waveformSampleCount,
}) {
  assert(sampleCount > 0);
  if (amplitudes.isEmpty) return List.filled(sampleCount, 0);

  final peaks = List.generate(sampleCount, (index) {
    final start = index * amplitudes.length ~/ sampleCount;
    final end = (((index + 1) * amplitudes.length) / sampleCount)
        .ceil()
        .clamp(start + 1, amplitudes.length);
    var peak = 0;
    for (var i = start; i < end && i < amplitudes.length; i++) {
      if (amplitudes[i] > peak) peak = amplitudes[i];
    }
    return peak;
  });
  final maximum = peaks.reduce(max);
  if (maximum <= 0) return List.filled(sampleCount, 0);

  return [
    for (final a in peaks)
      (sqrt(a / maximum) * 255).round().clamp(0, 255),
  ];
}

/// Records a voice message to an M4A (AAC) file using the `record`
/// plugin. Mirrors the Android `AndroidVoiceRecorder` constraints:
/// mono, 44.1 kHz, ~48 kbps, 1s minimum, 15min maximum.
class VoiceRecorder {
  VoiceRecorder();

  static const minDurationMs = 1000;
  static const postRollMs = 300;
  static const maxDurationMs = 15 * 60 * 1000;
  static const waveformSampleCount = 64;
  static const _amplitudeInterval = Duration(milliseconds: 50);

  // Created lazily — instantiating AudioRecorder invokes a platform
  // channel, which is unavailable in widget tests and before first use.
  AudioRecorder? _recorderInstance;
  AudioRecorder get _recorder => _recorderInstance ??= AudioRecorder();
  final List<int> _samples = [];
  StreamSubscription<Amplitude>? _ampSub;
  Timer? _maxTimer;
  String? _path;
  final Stopwatch _watch = Stopwatch();

  bool get isRecording => _path != null;

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<bool> start() async {
    if (_path != null) return false;
    if (!await _recorder.hasPermission()) return false;
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}${Platform.pathSeparator}vcr_${DateTime.now().millisecondsSinceEpoch}.m4a';
    _samples.clear();
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 48000,
        sampleRate: 44100,
        numChannels: 1,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      ),
      path: path,
    );
    _path = path;
    _watch
      ..reset()
      ..start();
    _ampSub = _recorder.onAmplitudeChanged(_amplitudeInterval).listen((a) {
      // dBFS -60..0 → 0..240; the waveform builder re-normalises anyway.
      _samples.add((((a.current + 60) / 60) * 240).round().clamp(0, 240));
    });
    _maxTimer = Timer(
      const Duration(milliseconds: maxDurationMs),
      () => stop(),
    );
    return true;
  }

  /// Stops and returns the recording, or null on failure/too short.
  Future<VoiceRecording?> stop() async {
    final path = _path;
    if (path == null) return null;
    _path = null;
    _watch.stop();
    await _ampSub?.cancel();
    _ampSub = null;
    _maxTimer?.cancel();
    _maxTimer = null;
    final elapsed = _watch.elapsedMilliseconds + postRollMs;
    String? out;
    try {
      out = await _recorder.stop();
    } catch (_) {
      out = null;
    }
    final file = File(out ?? path);
    if (!await file.exists()) return null;
    if (elapsed < minDurationMs) {
      try {
        await file.delete();
      } catch (_) {}
      return null;
    }
    final bytes = await file.readAsBytes();
    try {
      await file.delete();
    } catch (_) {}
    return VoiceRecording(
      bytes: bytes,
      mimeType: 'audio/mp4',
      fileExtension: 'm4a',
      durationMillis: elapsed,
      waveform: buildVoiceWaveform(List.of(_samples)),
    );
  }

  Future<void> cancel() async {
    final path = _path;
    _path = null;
    _watch.stop();
    await _ampSub?.cancel();
    _ampSub = null;
    _maxTimer?.cancel();
    _maxTimer = null;
    try {
      final out = await _recorder.stop();
      if (out != null) await File(out).delete();
    } catch (_) {}
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  void dispose() {
    cancel();
    _recorderInstance?.dispose();
    _recorderInstance = null;
  }
}
