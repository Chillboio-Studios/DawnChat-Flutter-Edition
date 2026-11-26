import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

class RawResponse {
  RawResponse(this.status, this.body, this.contentType);
  final int status;
  final Uint8List body;
  final String? contentType;
  String get text => utf8.decode(body, allowMalformed: true);
}

Map<String, String> _headers(Map<String, String> headers) =>
    kIsWeb ? headers : {'user-agent': 'DawnChat-Flutter', ...headers};

Future<RawResponse> _send(http.BaseRequest req, Duration timeout) async {
  final res = await http.Response.fromStream(await req.send()).timeout(
    timeout,
  );
  return RawResponse(
    res.statusCode,
    res.bodyBytes,
    res.headers['content-type'],
  );
}

/// HTTP via `package:http` on every platform.
Future<RawResponse> sendRequest(
  String method,
  String url, {
  Map<String, String> headers = const {},
  Uint8List? body,
}) async {
  final req = http.Request(method.toUpperCase(), Uri.parse(url))
    ..headers.addAll(_headers(headers));
  if (body != null) req.bodyBytes = body;
  return _send(req, const Duration(seconds: 60));
}

Future<RawResponse> sendUpload(
  String url, {
  Map<String, String> headers = const {},
  required String fileName,
  required String mime,
  required Uint8List bytes,
}) async {
  final req = http.MultipartRequest('POST', Uri.parse(url))
    ..headers.addAll(_headers(headers))
    ..files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName,
        contentType: http.MediaType.parse(mime),
      ),
    );
  return _send(req, const Duration(minutes: 30));
}

enum GatewayState { open, closed }

class GatewayMessage {
  GatewayMessage.open() : text = null, closedReason = null;
  GatewayMessage.text(this.text) : closedReason = null;
  GatewayMessage.closed(this.closedReason) : text = null;
  final String? text;
  final String? closedReason;
  bool get isOpen => text == null && closedReason == null;
}

/// Events websocket with keep-alive ping and exponential-backoff reconnect.
class GatewayConnection {
  StreamSubscription<dynamic>? _sub;
  WebSocketChannel? _channel;
  Timer? _ping;
  Timer? _retry;
  bool _stopped = false;
  bool _open = false;
  int _attempt = 0;
  final _pending = <String>[];
  final _controller = StreamController<GatewayMessage>.broadcast();

  Stream<GatewayMessage> get events => _controller.stream;

  void connect(String url) {
    close();
    _stopped = false;
    _connect(url);
  }

  void _connect(String url) {
    if (_stopped) return;
    final ch = WebSocketChannel.connect(Uri.parse(url));
    _channel = ch;
    bool current() => _channel == ch && !_stopped;
    ch.ready
        .then((_) {
          if (!current()) return;
          _attempt = 0;
          _open = true;
          _retry?.cancel();
          _retry = null;
          _controller.add(GatewayMessage.open());
          for (final text in _pending) {
            ch.sink.add(text);
          }
          _pending.clear();
          _ping = Timer.periodic(const Duration(seconds: 20), (_) {
            try {
              ch.sink.add('{"type":"Ping","data":0}');
            } catch (_) {}
          });
        })
        .catchError((Object e) {
          if (current()) _onClosed(url, e.toString());
        });
    _sub = ch.stream.listen(
      (m) {
        if (current()) _controller.add(GatewayMessage.text(m as String));
      },
      onDone: () {
        if (current()) _onClosed(url, 'closed');
      },
      onError: (Object e) {
        if (current()) _onClosed(url, e.toString());
      },
    );
  }

  void _onClosed(String url, String reason) {
    _ping?.cancel();
    _ping = null;
    _open = false;
    if (_stopped) return;
    _controller.add(GatewayMessage.closed(reason));
    _attempt++;
    if (_retry != null) return;
    final ms = (500 << (_attempt > 5 ? 5 : _attempt)).clamp(0, 15000);
    _retry = Timer(Duration(milliseconds: ms), () {
      _retry = null;
      _connect(url);
    });
  }

  void send(Map<String, dynamic> payload) {
    final text = jsonEncode(payload);
    final ch = _channel;
    if (ch == null || !_open) {
      _pending.add(text);
    } else {
      ch.sink.add(text);
    }
  }

  void close() {
    _stopped = true;
    _open = false;
    _pending.clear();
    _ping?.cancel();
    _ping = null;
    _retry?.cancel();
    _retry = null;
    _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
  }
}
