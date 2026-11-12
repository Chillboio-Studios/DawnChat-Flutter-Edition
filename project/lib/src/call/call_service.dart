import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android ongoing-call foreground service (CallStyle notification with
/// mute/hang-up actions), port of the Android app's `OngoingCallService`.
/// No-ops on every other platform.
class CallService {
  CallService._();

  static const _method = MethodChannel('dawnchat/call_service');
  static const _events = EventChannel('dawnchat/call_events');

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static StreamSubscription<String>? _sub;
  static void Function(String event)? onEvent;

  /// Starts listening for hang-up/mute actions from the notification.
  static void listen(void Function(String event) handler) {
    onEvent = handler;
    if (!_supported || _sub != null) return;
    _sub = _events.receiveBroadcastStream().cast<String>().listen((e) {
      handler(e);
    });
  }

  static Future<void> start(String channelId, String? channelName) async {
    if (!_supported) return;
    try {
      await _method.invokeMethod('start', {
        'channelId': channelId,
        'channelName': channelName,
      });
    } on PlatformException catch (_) {}
  }

  static Future<void> stop() async {
    if (!_supported) return;
    try {
      await _method.invokeMethod('stop');
    } on PlatformException catch (_) {}
  }

  static Future<void> setMicMuted(bool muted) async {
    if (!_supported) return;
    try {
      await _method.invokeMethod('setMicMuted', {'muted': muted});
    } on PlatformException catch (_) {}
  }
}
