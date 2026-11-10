import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../rust/api/gateway.dart' as rust_gw;
import '../rust/api/http.dart' as rust_http;

class RawResponse {
  RawResponse(this.status, this.body, this.contentType);
  final int status;
  final Uint8List body;
  final String? contentType;
  String get text => utf8.decode(body, allowMalformed: true);
}

/// HTTP over the Rust (reqwest) backend on native platforms, `package:http` on web.
Future<RawResponse> sendRequest(
  String method,
  String url, {
  Map<String, String> headers = const {},
  Uint8List? body,
}) async {
  if (kIsWeb) {
    final req = http.Request(method.toUpperCase(), Uri.parse(url))
      ..headers.addAll(headers);
    if (body != null) req.bodyBytes = body;
    final res = await http.Response.fromStream(await req.send());
    return RawResponse(
      res.statusCode,
      res.bodyBytes,
      res.headers['content-type'],
    );
  }
  final res = await rust_http.httpRequest(
    method: method,
    url: url,
    headers: headers.entries.map((e) => (e.key, e.value)).toList(),
    body: body,
  );
  return RawResponse(res.status, res.body, res.contentType);
}

Future<RawResponse> sendUpload(
  String url, {
  Map<String, String> headers = const {},
  required String fileName,
  required String mime,
  required Uint8List bytes,
}) async {
  if (kIsWeb) {
    final req = http.MultipartRequest('POST', Uri.parse(url))
      ..headers.addAll(headers)
      ..files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: fileName),
      );
    final res = await http.Response.fromStream(await req.send());
    return RawResponse(
      res.statusCode,
      res.bodyBytes,
      res.headers['content-type'],
    );
  }
  final res = await rust_http.httpUpload(
    url: url,
    headers: headers.entries.map((e) => (e.key, e.value)).toList(),
    field: 'file',
    fileName: fileName,
    mime: mime,
    bytes: bytes,
  );
  return RawResponse(res.status, res.body, res.contentType);
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

/// Events websocket with keep-alive and reconnect. Rust on native, Dart on web.
class GatewayConnection {
  StreamSubscription<dynamic>? _sub;
  WebSocketChannel? _channel;
  Timer? _ping;
  Timer? _retry;
  bool _stopped = false;
  int _attempt = 0;
  final _controller = StreamController<GatewayMessage>.broadcast();

  Stream<GatewayMessage> get events => _controller.stream;

  void connect(String url) {
    close();
    _stopped = false;
    if (kIsWeb) {
      _webConnect(url);
    } else {
      _sub = rust_gw.gatewayConnect(url: url).listen((e) {
        switch (e) {
          case rust_gw.GatewayEvent_Open():
            _controller.add(GatewayMessage.open());
          case rust_gw.GatewayEvent_Text(:final field0):
            _controller.add(GatewayMessage.text(field0));
          case rust_gw.GatewayEvent_Closed(:final field0):
            _controller.add(GatewayMessage.closed(field0));
        }
      });
    }
  }

  void _webConnect(String url) {
    if (_stopped) return;
    final ch = WebSocketChannel.connect(Uri.parse(url));
    _channel = ch;
    ch.ready
        .then((_) {
          _attempt = 0;
          _controller.add(GatewayMessage.open());
          _ping = Timer.periodic(const Duration(seconds: 20), (_) {
            ch.sink.add('{"type":"Ping","data":0}');
          });
        })
        .catchError((Object e) {
          _controller.add(GatewayMessage.closed(e.toString()));
        });
    _sub = ch.stream.listen(
      (m) => _controller.add(GatewayMessage.text(m as String)),
      onDone: () => _onWebClosed(url, 'closed'),
      onError: (Object e) => _onWebClosed(url, e.toString()),
    );
  }

  void _onWebClosed(String url, String reason) {
    _ping?.cancel();
    if (_stopped) return;
    _controller.add(GatewayMessage.closed(reason));
    _attempt++;
    final ms = (500 << (_attempt > 5 ? 5 : _attempt)).clamp(0, 15000);
    _retry = Timer(Duration(milliseconds: ms), () => _webConnect(url));
  }

  void send(Map<String, dynamic> payload) {
    final text = jsonEncode(payload);
    if (kIsWeb) {
      _channel?.sink.add(text);
    } else {
      rust_gw.gatewaySend(text: text);
    }
  }

  void close() {
    _stopped = true;
    _ping?.cancel();
    _retry?.cancel();
    _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
    if (!kIsWeb) rust_gw.gatewayDisconnect();
  }
}
