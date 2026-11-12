import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../theme/tokens.dart';

/// Voice message bubble: play button, waveform and duration.
/// Port of the Android `VoiceMessagePlayer` using the shared metadata
/// written by [VoiceRecorder.messageContent].
class VoiceMessageView extends StatefulWidget {
  const VoiceMessageView({
    super.key,
    required this.durationMs,
    required this.waveform,
    this.url,
  });

  /// Remote audio URL; null while the message is still pending upload.
  final String? url;
  final int durationMs;
  final List<int> waveform;

  @override
  State<VoiceMessageView> createState() => _VoiceMessageViewState();
}

class _VoiceMessageViewState extends State<VoiceMessageView> {
  Player? _player;
  bool playing = false;
  Duration pos = Duration.zero;
  final _subs = <StreamSubscription>[];

  Player? get _p {
    final url = widget.url;
    if (url == null) return null;
    if (_player != null) return _player;
    final p = _player = Player();
    _subs
      ..add(
        p.stream.playing.listen((v) {
          if (mounted) setState(() => playing = v);
        }),
      )
      ..add(
        p.stream.position.listen((v) {
          if (mounted) setState(() => pos = v);
        }),
      );
    p.open(Media(url), play: false);
    return p;
  }

  void _toggle() {
    final p = _p;
    if (p == null) return;
    p.playOrPause();
  }

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final total = Duration(milliseconds: widget.durationMs);
    final progress = total.inMilliseconds <= 0
        ? 0.0
        : (pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    return Container(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 340),
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: Gap.xs),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: br(Radius_.lg),
      ),
      child: Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 28,
            ),
            color: cs.primary,
            onPressed: widget.url == null ? null : _toggle,
          ),
          Expanded(
            child: SizedBox(
              height: 36,
              child: CustomPaint(
                painter: _WavePainter(
                  samples: widget.waveform,
                  progress: progress,
                  played: cs.primary,
                  idle: cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(width: Gap.sm),
          Text(
            _fmt(playing || pos > Duration.zero ? pos : total),
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.samples,
    required this.progress,
    required this.played,
    required this.idle,
  });

  final List<int> samples;
  final double progress;
  final Color played, idle;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;
    final n = samples.length;
    final barW = size.width / n;
    final playedCount = (n * progress).floor();
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < n; i++) {
      final h = (size.height * 0.9) * (samples[i] / 255.0) + 2;
      paint
        ..color = i < playedCount ? played : idle
        ..strokeWidth = (barW * 0.55).clamp(1.5, 4.0);
      final x = i * barW + barW / 2;
      canvas.drawLine(
        Offset(x, (size.height - h) / 2),
        Offset(x, (size.height + h) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.progress != progress || old.samples != samples;
}
