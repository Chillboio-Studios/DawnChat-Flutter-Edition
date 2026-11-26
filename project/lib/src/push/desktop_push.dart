import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Web Push (RFC 8030/8291) user agent for desktop platforms that have no
/// native push service. Talks to the Mozilla autopush websocket, so
/// notifications arrive while the app is running in the background or the
/// tray, using the same `/push/subscribe` flow as the web client.
///
/// Pure-Dart port of the former Rust implementation; subscription keys are
/// stored in the same format so existing saved subscriptions keep working.

const _autopushUrl = 'wss://push.services.mozilla.com/';
final _random = Random.secure();
final _ecParams = ECDomainParameters('prime256v1');

class PushSubscription {
  const PushSubscription({
    required this.endpoint,
    required this.p256Dh,
    required this.auth,
    required this.privateKey,
    required this.uaid,
    required this.channelId,
  });

  final String endpoint;
  final String p256Dh;
  final String auth;
  final String privateKey;
  final String uaid;
  final String channelId;
}

sealed class PushEvent {
  const PushEvent();
}

final class PushEventRegistered extends PushEvent {
  const PushEventRegistered(this.subscription);
  final PushSubscription subscription;
}

final class PushEventNotification extends PushEvent {
  const PushEventNotification(this.payload);
  final String payload;
}

final class PushEventClosed extends PushEvent {
  const PushEventClosed(this.reason);
  final String reason;
}

/// Mutable session state; the public [PushSubscription] is a snapshot.
class _Sub {
  _Sub({
    required this.p256Dh,
    required this.auth,
    required this.privateKey,
    required this.channelId,
    this.endpoint = '',
    this.uaid = '',
  });

  String endpoint;
  final String p256Dh;
  final String auth;
  final String privateKey;
  String uaid;
  final String channelId;
  ECPrivateKey? _ecPriv;
  Uint8List? _uaPublic;
}

/// Live autopush connection owned by one [_session] call.
class _Session {
  WebSocketChannel? channel;
  StreamSubscription<dynamic>? socketSub;
  Timer? keepalive;

  Future<void> dispose() async {
    keepalive?.cancel();
    keepalive = null;
    final sub = socketSub;
    socketSub = null;
    await sub?.cancel();
    final ch = channel;
    channel = null;
    if (ch != null) {
      try {
        await ch.sink.close();
      } catch (_) {}
    }
  }
}

_Session? _current;
Completer<void>? _stop;
StreamController<PushEvent>? _events;

String _b64url(Uint8List bytes) => base64Url.encode(bytes).replaceAll('=', '');

Uint8List _b64urlDecode(String v) {
  var s = v.replaceAll('-', '+').replaceAll('_', '/');
  while (s.length % 4 != 0) {
    s += '=';
  }
  return base64.decode(s);
}

Uint8List _randomBytes(int n) {
  final b = Uint8List(n);
  for (var i = 0; i < n; i++) {
    b[i] = _random.nextInt(256);
  }
  return b;
}

BigInt _bytesToBigInt(Uint8List bytes) {
  var v = BigInt.zero;
  for (final b in bytes) {
    v = (v << 8) | BigInt.from(b);
  }
  return v;
}

Uint8List _bigIntToBytes(BigInt v, int length) {
  final out = Uint8List(length);
  for (var i = length - 1; i >= 0; i--) {
    out[i] = (v & BigInt.from(0xff)).toInt();
    v >>= 8;
  }
  return out;
}

String _newChannelId() {
  final b = _randomBytes(16);
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String hex(int i) => b[i].toRadixString(16).padLeft(2, '0');
  return '${List.generate(4, hex).join()}-'
      '${List.generate(2, (i) => hex(i + 4)).join()}-'
      '${List.generate(2, (i) => hex(i + 6)).join()}-'
      '${List.generate(2, (i) => hex(i + 8)).join()}-'
      '${List.generate(6, (i) => hex(i + 10)).join()}';
}

_Sub _freshSubscription() {
  final n = _ecParams.n;
  BigInt d;
  do {
    d = _bytesToBigInt(_randomBytes(32));
  } while (d <= BigInt.zero || d >= n);

  final publicBytes = (_ecParams.G * d)!.getEncoded(false);
  final auth = _randomBytes(16);
  return _Sub(
    p256Dh: _b64url(publicBytes),
    auth: _b64url(auth),
    privateKey: _b64url(_bigIntToBytes(d, 32)),
    channelId: _newChannelId(),
  ).._ecPriv = ECPrivateKey(d, _ecParams);
}

_Sub _fromSaved(PushSubscription saved) => _Sub(
  endpoint: saved.endpoint,
  p256Dh: saved.p256Dh,
  auth: saved.auth,
  privateKey: saved.privateKey,
  uaid: saved.uaid,
  channelId: saved.channelId,
);

ECPrivateKey _privateKey(_Sub sub) {
  return sub._ecPriv ??= ECPrivateKey(
    _bytesToBigInt(_b64urlDecode(sub.privateKey)),
    _ecParams,
  );
}

Uint8List _uaPublicBytes(_Sub sub) {
  return sub._uaPublic ??= (_ecParams.G * _privateKey(sub).d)!.getEncoded(
    false,
  );
}

Uint8List _hkdf(Uint8List salt, Uint8List ikm, Uint8List info, int length) {
  final derivator = HKDFKeyDerivator(SHA256Digest());
  derivator.init(HkdfParameters(ikm, length, salt, info));
  return derivator.process(Uint8List(0));
}

Uint8List _concat(List<List<int>> parts) {
  var len = 0;
  for (final p in parts) {
    len += p.length;
  }
  final out = Uint8List(len);
  var off = 0;
  for (final p in parts) {
    out.setRange(off, off + p.length, p);
    off += p.length;
  }
  return out;
}

String? _decrypt(_Sub sub, Uint8List payload) {
  if (payload.length <= 21) return null;
  final salt = payload.sublist(0, 16);
  final idLen = payload[20];
  if (payload.length <= 21 + idLen) return null;
  final asPublicBytes = payload.sublist(21, 21 + idLen);
  final ciphertext = payload.sublist(21 + idLen);

  final priv = _privateKey(sub);
  final asPoint = _ecParams.curve.decodePoint(asPublicBytes);
  if (asPoint == null) return null;

  final agreement = ECDHBasicAgreement()..init(priv);
  final sharedX = agreement.calculateAgreement(
    ECPublicKey(asPoint, _ecParams),
  );
  final sharedSecret = _bigIntToBytes(sharedX, 32);

  final authSecret = _b64urlDecode(sub.auth);
  final info = _concat([
    utf8.encode('WebPush: info'),
    Uint8List.fromList([0]),
    _uaPublicBytes(sub),
    asPublicBytes,
  ]);
  final ikm = _hkdf(authSecret, sharedSecret, info, 32);

  final cek = _hkdf(
    salt,
    ikm,
    _concat([
      utf8.encode('Content-Encoding: aes128gcm'),
      Uint8List.fromList([0]),
    ]),
    16,
  );
  final nonce = _hkdf(
    salt,
    ikm,
    _concat([utf8.encode('Content-Encoding: nonce'), Uint8List.fromList([0])]),
    12,
  );

  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      false,
      AEADParameters(KeyParameter(cek), 128, nonce, Uint8List(0)),
    );
  final plain = Uint8List(cipher.getOutputSize(ciphertext.length));
  var len = cipher.processBytes(ciphertext, 0, ciphertext.length, plain, 0);
  len += cipher.doFinal(plain, len);
  final data = plain.sublist(0, len);

  // Strip the RFC 8188 padding delimiter and any pad bytes before it.
  var end = data.length;
  while (end > 0) {
    final last = data[end - 1];
    end--;
    if (last == 0x02 || last == 0x01) break;
  }
  return utf8.decode(data.sublist(0, end), allowMalformed: true);
}

void _emit(PushEvent event) {
  final c = _events;
  if (c != null && !c.isClosed) c.add(event);
}

void _safeSend(WebSocketChannel ch, Object data) {
  try {
    ch.sink.add(jsonEncode(data));
  } catch (_) {}
}

void _onMessage(
  dynamic message,
  WebSocketChannel ch,
  String vapidKey,
  _Sub sub,
) {
  if (message is! String) return;
  final Object? v;
  try {
    v = jsonDecode(message);
  } catch (_) {
    return;
  }
  if (v is! Map) return;
  switch (v['messageType']) {
    case 'hello':
      sub.uaid = v['uaid'] as String? ?? '';
      _safeSend(ch, {
        'messageType': 'register',
        'channelID': sub.channelId,
        'key': vapidKey,
      });
    case 'register':
      final endpoint = v['pushEndpoint'] as String?;
      if (endpoint != null && endpoint.isNotEmpty) {
        sub.endpoint = endpoint;
        _emit(
          PushEventRegistered(
            PushSubscription(
              endpoint: endpoint,
              p256Dh: sub.p256Dh,
              auth: sub.auth,
              privateKey: sub.privateKey,
              uaid: sub.uaid,
              channelId: sub.channelId,
            ),
          ),
        );
      }
    case 'notification':
      final data = v['data'] as String?;
      final channel = v['channelID'] as String?;
      final version = v['version'] as String?;
      if (data != null && channel != null && version != null) {
        try {
          final plain = _decrypt(sub, _b64urlDecode(data));
          if (plain != null) _emit(PushEventNotification(plain));
        } catch (_) {}
        _safeSend(ch, {
          'messageType': 'ack',
          'updates': [
            {'channelID': channel, 'version': version, 'code': 100},
          ],
        });
      }
  }
}

/// Runs one autopush session. Returns the disconnect reason, or null when the
/// session ended because [stop] completed.
Future<String?> _session(String vapidKey, _Sub sub, Completer<void> stop) async {
  final session = _Session();
  _current = session;
  final ch = WebSocketChannel.connect(Uri.parse(_autopushUrl));
  session.channel = ch;
  try {
    await ch.ready;
    _safeSend(ch, {
      'messageType': 'hello',
      'use_webpush': true,
      'channelIDs': sub.uaid.isEmpty ? <String>[] : [sub.channelId],
      if (sub.uaid.isNotEmpty) 'uaid': sub.uaid,
    });
  } catch (e) {
    if (_current == session) _current = null;
    await session.dispose();
    rethrow;
  }

  session.keepalive = Timer.periodic(const Duration(seconds: 45), (_) {
    _safeSend(ch, '{}');
  });

  final socketDone = Completer<String>();
  session.socketSub = ch.stream.listen(
    (m) => _onMessage(m, ch, vapidKey, sub),
    onDone: () {
      if (!socketDone.isCompleted) socketDone.complete('disconnected');
    },
    onError: (Object e) {
      if (!socketDone.isCompleted) socketDone.complete('$e');
    },
    cancelOnError: false,
  );

  String reason;
  try {
    reason = await Future.any([
      socketDone.future,
      stop.future.then((_) => ''),
    ]);
  } finally {
    if (_current == session) _current = null;
    await session.dispose();
  }
  return reason.isEmpty ? null : reason;
}

/// Starts (or resumes, when [saved] is given) a desktop web-push subscription.
Stream<PushEvent> pushStart({
  required String vapidKey,
  PushSubscription? saved,
}) {
  pushStop();
  final controller = StreamController<PushEvent>();
  _events = controller;
  final stop = Completer<void>();
  _stop = stop;
  final sub = saved == null ? _freshSubscription() : _fromSaved(saved);

  () async {
    var attempt = 0;
    while (!stop.isCompleted) {
      String? reason;
      try {
        reason = await _session(vapidKey, sub, stop);
      } catch (e) {
        reason = '$e';
      }
      if (stop.isCompleted) break;
      if (reason != null) {
        _emit(PushEventClosed(reason));
      }
      attempt++;
      final secs = min(120, 2 << min(attempt, 5));
      await Future.any([Future.delayed(Duration(seconds: secs)), stop.future]);
    }
    await controller.close();
  }();

  return controller.stream;
}

Future<void> pushStop() async {
  final stop = _stop;
  _stop = null;
  stop?.complete();
  final session = _current;
  _current = null;
  final c = _events;
  _events = null;
  await session?.dispose();
  await c?.close();
}
