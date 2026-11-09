import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

String _b64url(ByteBuffer buf) =>
    base64Url.encode(buf.asUint8List()).replaceAll('=', '');

Uint8List _fromB64url(String v) {
  final s = v.replaceAll('-', '+').replaceAll('_', '/');
  return base64.decode(s.padRight((s.length + 3) ~/ 4 * 4, '='));
}

Future<bool> requestPermission() async {
  final res = await web.Notification.requestPermission().toDart;
  return res.toDart == 'granted';
}

/// Registers the push service worker and subscribes with the instance VAPID key.
Future<Map<String, String>?> subscribe(String vapidKey) async {
  final sw = web.window.navigator.serviceWorker;
  await sw.register('push_sw.js'.toJS).toDart;
  final reg = await sw.ready.toDart;

  var sub = await reg.pushManager.getSubscription().toDart;
  final wanted = _fromB64url(vapidKey);
  if (sub != null) {
    final key = sub.options.applicationServerKey;
    final have = key == null ? null : _b64url(key.toDart);
    if (have != _b64url(wanted.buffer)) {
      await sub.unsubscribe().toDart;
      sub = null;
    }
  }
  sub ??= await reg.pushManager
      .subscribe(
        web.PushSubscriptionOptionsInit(
          userVisibleOnly: true,
          applicationServerKey: wanted.toJS,
        ),
      )
      .toDart;

  final p256dh = sub.getKey('p256dh');
  final auth = sub.getKey('auth');
  return {
    'endpoint': sub.endpoint,
    'p256dh': p256dh == null ? '' : _b64url(p256dh.toDart),
    'auth': auth == null ? '' : _b64url(auth.toDart),
  };
}

Future<void> unsubscribe() async {
  final reg = await web.window.navigator.serviceWorker.getRegistration().toDart;
  final sub = await reg?.pushManager.getSubscription().toDart;
  await sub?.unsubscribe().toDart;
}

void showLocal(String title, String body) {
  if (web.Notification.permission == 'granted') {
    web.Notification(title, web.NotificationOptions(body: body));
  }
}
