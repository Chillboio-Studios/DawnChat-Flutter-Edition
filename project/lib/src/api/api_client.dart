import 'dart:convert';
import 'dart:typed_data';

import 'transport.dart';

class ApiException implements Exception {
  ApiException(this.status, this.type, [this.body]);
  final int status;
  final String type;
  final dynamic body;
  @override
  String toString() => type.isEmpty ? 'HTTP $status' : type;
}

class InstanceConfig {
  InstanceConfig(this.raw);
  final Map<String, dynamic> raw;

  Map<String, dynamic> get features =>
      (raw['features'] as Map?)?.cast<String, dynamic>() ?? {};
  String get ws => raw['ws'] as String;
  String get app => (raw['app'] as String?) ?? '';
  String get vapid => (raw['vapid'] as String?) ?? '';
  String get autumnUrl =>
      ((features['autumn'] as Map?)?['url'] as String?) ?? '';
  String get januaryUrl =>
      ((features['january'] as Map?)?['url'] as String?) ?? '';
  bool get captchaEnabled =>
      ((features['captcha'] as Map?)?['enabled'] as bool?) ?? false;
  String get captchaKey =>
      ((features['captcha'] as Map?)?['key'] as String?) ?? '';
  bool get emailVerification => (features['email'] as bool?) ?? false;
  bool get invite_only => (features['invite_only'] as bool?) ?? false;
  Map<String, dynamic> get legalLinks =>
      (features['legal_links'] as Map?)?.cast<String, dynamic>() ?? {};
  Map<String, dynamic> get limits =>
      (features['limits'] as Map?)?.cast<String, dynamic>() ?? {};
  bool get video => videoAllowed;

  /// Whether the logged-in account is still within the `new_user` limit tier.
  /// Set by ClientStore after login based on account age vs `new_user_hours`.
  bool newUserAccount = false;

  Map<String, dynamic> get _userLimits {
    final l = limits;
    final global = (l['global'] as Map?)?.cast<String, dynamic>() ?? {};
    final tier = newUserAccount
        ? (l['new_user'] ?? l['default'])
        : (l['default'] ?? l['new_user']);
    return (tier as Map?)?.cast<String, dynamic>() ??
        global.cast<String, dynamic>();
  }

  /// Max camera/screenshare resolution [width, height] in pixels for this user.
  /// A 0 component means unlimited.
  List<int> get videoResolution {
    final r = (_userLimits['video_resolution'] as List?) ?? const [0, 0];
    return [
      (r.isNotEmpty ? r[0] : 0) as int,
      (r.length > 1 ? r[1] : 0) as int,
    ];
  }

  /// Max voice bitrate for this user.
  int get voiceQuality =>
      (_userLimits['voice_quality'] as num?)?.toInt() ?? 64000;

  /// Whether the user may use camera/video at all.
  bool get videoAllowed => (_userLimits['video'] as bool?) ?? true;
  int get messageLength =>
      (_userLimits['message_length'] as num?)?.toInt() ?? 2000;
  int get messageAttachments =>
      (_userLimits['message_attachments'] as num?)?.toInt() ?? 5;

  /// Upload size limit in bytes for a given autumn tag (attachments, avatars, icons, banners, backgrounds, emojis).
  int fileLimit(String tag) =>
      (((_userLimits['file_upload_size_limits'] as Map?)?[tag]) as num?)
          ?.toInt() ??
      20000000;
}

class ApiClient {
  ApiClient(this.baseUrl);

  String baseUrl;
  String? token;
  InstanceConfig? config;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'x-session-token': ?token,
  };

  Future<InstanceConfig> fetchConfig() async {
    final res = await request('GET', '/');
    config = InstanceConfig((res as Map).cast<String, dynamic>());
    return config!;
  }

  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
  }) async {
    var uri = '$baseUrl$path';
    if (query != null && query.isNotEmpty) {
      final qs = query.entries
          .where((e) => e.value != null)
          .map(
            (e) =>
                '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent('${e.value}')}',
          )
          .join('&');
      uri += '?$qs';
    }
    final res = await sendRequest(
      method,
      uri,
      headers: {..._headers, ...?headers},
      body: body == null
          ? null
          : Uint8List.fromList(utf8.encode(jsonEncode(body))),
    );
    dynamic parsed;
    if (res.body.isNotEmpty) {
      try {
        parsed = jsonDecode(res.text);
      } catch (_) {
        parsed = res.text;
      }
    }
    if (res.status >= 400) {
      final type = parsed is Map ? (parsed['type'] as String? ?? '') : '';
      throw ApiException(res.status, type, parsed);
    }
    return parsed;
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      request('GET', path, query: query);
  Future<dynamic> post(String path, [Object? body]) =>
      request('POST', path, body: body);
  Future<dynamic> patch(String path, [Object? body]) =>
      request('PATCH', path, body: body);
  Future<dynamic> put(String path, [Object? body]) =>
      request('PUT', path, body: body);
  Future<dynamic> delete(String path, {Object? body}) =>
      request('DELETE', path, body: body);

  /// Uploads to Autumn and returns the file id.
  Future<String> uploadFile(
    String tag,
    String name,
    String mime,
    Uint8List bytes,
  ) async {
    final url = '${config!.autumnUrl}/$tag';
    final res = await sendUpload(
      url,
      headers: {'x-session-token': ?token},
      fileName: name,
      mime: mime,
      bytes: bytes,
    );
    if (res.status >= 400) throw ApiException(res.status, 'UploadFailed');
    return (jsonDecode(res.text) as Map)['id'] as String;
  }

  String? fileUrl(String tag, Map? file, {int? width}) {
    final id = file?['_id'] as String?;
    final base = config?.autumnUrl;
    if (id == null || base == null || base.isEmpty) return null;
    final minSide =
        (tag == 'icons' || tag == 'avatars') && width != null && width < 256
        ? 256
        : width;
    final q = minSide != null ? '?max_side=$minSide' : '';
    return '$base/$tag/$id$q';
  }

  String defaultAvatar(String userId) =>
      '$baseUrl/users/$userId/default_avatar';
}
