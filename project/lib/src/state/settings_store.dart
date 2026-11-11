import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/i18n.dart';

const interfaceFonts = <String>[
  'Atkinson Hyperlegible',
  'Bitter',
  'Comic Neue',
  'IBM Plex Sans',
  'Inter',
  'Lato',
  'Lexend',
  'Montserrat',
  'Noto Sans',
  'Open Sans',
  'OpenDyslexic',
  'Plus Jakarta Sans',
  'Poppins',
  'Raleway',
  'Roboto',
  'Ubuntu',
];

const monospaceFonts = <String>[
  'Fira Code',
  'IBM Plex Mono',
  'JetBrains Mono',
  'Roboto Mono',
  'Source Code Pro',
  'Space Mono',
  'Ubuntu Mono',
];

const m3Variants = <String>[
  'monochrome',
  'neutral',
  'tonal_spot',
  'vibrant',
  'expressive',
  'fidelity',
  'content',
  'rainbow',
  'fruit_salad',
];

const unicodeEmojiPacks = <String>[
  'fluent-3d',
  'fluent-color',
  'fluent-flat',
  'mutant',
  'noto',
  'twemoji',
];

const soundKeys = <String>[
  'message',
  'mute',
  'unmute',
  'deafen',
  'undeafen',
  'userJoinVoice',
  'userLeaveVoice',
  'userMoved',
  'streamStart',
  'streamEnd',
  'streamViewerJoin',
  'streamViewerLeave',
  'ringtoneIncoming',
  'ringtoneOutgoing',
];

/// Persistent client settings; keys and defaults mirror the web client's state stores.
class SettingsStore extends ChangeNotifier {
  SettingsStore(this._prefs) {
    final raw = _prefs.getString(_key);
    if (raw != null) {
      try {
        _data.addAll(Map<String, dynamic>.from(jsonDecode(raw) as Map));
      } catch (_) {}
    }
  }

  static const _key = 'dawnchat.state';
  final SharedPreferences _prefs;
  final Map<String, dynamic> _data = {};

  static Future<SettingsStore> load() async =>
      SettingsStore(await SharedPreferences.getInstance());

  T _get<T>(String key, T fallback) {
    final v = _data[key];
    return v is T ? v : fallback;
  }

  void _set(String key, Object? value) {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
    _prefs.setString(_key, jsonEncode(_data));
    notifyListeners();
  }

  // --- theme ---
  String get mode => _get('theme.mode', 'system');
  set mode(String v) => _set('theme.mode', v);
  String get m3Accent => _get('theme.m3Accent', '#5470ec');
  set m3Accent(String v) => _set('theme.m3Accent', v);
  double get m3Contrast => _get<num>('theme.m3Contrast', 0).toDouble();
  set m3Contrast(double v) => _set('theme.m3Contrast', v);
  String get m3Variant => _get('theme.m3Variant', 'tonal_spot');
  set m3Variant(String v) => _set('theme.m3Variant', v);
  String get interfaceFont => _get('theme.interfaceFont', 'Inter');
  set interfaceFont(String v) => _set('theme.interfaceFont', v);
  String get monospaceFont => _get('theme.monospaceFont', 'Fira Code');
  set monospaceFont(String v) => _set('theme.monospaceFont', v);
  bool get blur => _get('theme.blur', true);
  set blur(bool v) => _set('theme.blur', v);
  double get messageSize => _get<num>('theme.messageSize', 14).toDouble();
  set messageSize(double v) => _set('theme.messageSize', v);
  double get messageGroupSpacing =>
      _get<num>('theme.messageGroupSpacing', 12).toDouble();
  set messageGroupSpacing(double v) => _set('theme.messageGroupSpacing', v);

  // --- settings ---
  String get desktopNotifications =>
      _get('settings.notifications:desktop', 'default');
  set desktopNotifications(String v) =>
      _set('settings.notifications:desktop', v);
  String get pushNotifications =>
      _get('settings.notifications:push', 'default');
  set pushNotifications(String v) => _set('settings.notifications:push', v);
  String get unicodeEmoji =>
      _get('settings.appearance:unicode_emoji', 'fluent-3d');
  set unicodeEmoji(String v) => _set('settings.appearance:unicode_emoji', v);
  bool get showSendButton => _get('settings.appearance:show_send_button', true);
  set showSendButton(bool v) => _set('settings.appearance:show_send_button', v);
  bool get compactMode => _get('settings.appearance:compact_mode', false);
  set compactMode(bool v) => _set('settings.appearance:compact_mode', v);
  bool get copyId => _get('settings.advanced:copy_id', false);
  set copyId(bool v) => _set('settings.advanced:copy_id', v);
  bool get adminPanel => _get('settings.advanced:admin_panel', false);
  set adminPanel(bool v) => _set('settings.advanced:admin_panel', v);

  // --- locale ---
  String get lang => _get('locale.lang', preferredLanguageCode());
  set lang(String v) => _set('locale.lang', v);
  String get dateFormat => _get('locale.dateFormat', 'DD/MM/YYYY');
  set dateFormat(String v) => _set('locale.dateFormat', v);
  String get timeFormat => _get('locale.timeFormat', 'HH:mm');
  set timeFormat(String v) => _set('locale.timeFormat', v);

  // --- sounds ---
  bool soundEnabled(String key) => _get('sounds.$key', true);
  void toggleSound(String key) => _set('sounds.$key', !soundEnabled(key));

  // --- voice ---
  String? get audioInput =>
      _get<String?>('voice.preferredAudioInputDevice', null);
  set audioInput(String? v) => _set('voice.preferredAudioInputDevice', v);
  String? get audioOutput =>
      _get<String?>('voice.preferredAudioOutputDevice', null);
  set audioOutput(String? v) => _set('voice.preferredAudioOutputDevice', v);
  String? get videoInput => _get<String?>('voice.preferredVideoDevice', null);
  set videoInput(String? v) => _set('voice.preferredVideoDevice', v);
  bool get echoCancellation => _get('voice.echoCancellation', true);
  set echoCancellation(bool v) => _set('voice.echoCancellation', v);
  String get noiseSuppression => _get('voice.noiseSupression', 'enhanced');
  set noiseSuppression(String v) => _set('voice.noiseSupression', v);
  bool get autoGainControl => _get('voice.autoGainControl', true);
  set autoGainControl(bool v) => _set('voice.autoGainControl', v);
  String get screenShareQuality => _get('voice.screenShareQuality', 'low');
  set screenShareQuality(String v) => _set('voice.screenShareQuality', v);
  bool get screenShareQualityAsk => _get('voice.screenShareQualityAsk', true);
  set screenShareQualityAsk(bool v) => _set('voice.screenShareQualityAsk', v);
  bool get screenShareAudio => _get('voice.screenShareAudio', true);
  set screenShareAudio(bool v) => _set('voice.screenShareAudio', v);
  double get inputVolume => _get<num>('voice.inputVolume', 1).toDouble();
  set inputVolume(double v) => _set('voice.inputVolume', v);
  double get outputVolume => _get<num>('voice.outputVolume', 1).toDouble();
  set outputVolume(double v) => _set('voice.outputVolume', v);
  bool get deafen => _get('voice.deafen', false);
  set deafen(bool v) => _set('voice.deafen', v);
  bool get micOn => _get('voice.micOn', true);
  set micOn(bool v) => _set('voice.micOn', v);

  // --- desktop (native) ---
  bool get minimiseToTray => _get('native.minimiseToTray', false);
  set minimiseToTray(bool v) => _set('native.minimiseToTray', v);
  bool get startMinimisedToTray => _get('native.startMinimisedToTray', false);
  set startMinimisedToTray(bool v) => _set('native.startMinimisedToTray', v);
  bool get customFrame => _get('native.customFrame', true);
  set customFrame(bool v) => _set('native.customFrame', v);
  bool get discordRpc => _get('native.discordRpc', false);
  set discordRpc(bool v) => _set('native.discordRpc', v);
  bool get spellchecker => _get('native.spellchecker', true);
  set spellchecker(bool v) => _set('native.spellchecker', v);
  bool get hardwareAcceleration => _get('native.hardwareAcceleration', true);
  set hardwareAcceleration(bool v) => _set('native.hardwareAcceleration', v);

  // --- auth / layout ---
  String _ak(String? host, String f) => 'auth.${host ?? 'default'}.$f';
  String? tokenFor(String? host) => _get<String?>(_ak(host, 'token'), null);
  String? sessionIdFor(String? host) =>
      _get<String?>(_ak(host, 'sessionId'), null);
  String? userIdFor(String? host) => _get<String?>(_ak(host, 'userId'), null);
  void setSession(
    String? host,
    String? token,
    String? sessionId,
    String? userId,
  ) {
    for (final f in ['token', 'sessionId', 'userId']) {
      _data.remove(_ak(host, f));
    }
    if (token != null) {
      _data[_ak(host, 'token')] = token;
      _data[_ak(host, 'sessionId')] = sessionId;
      _data[_ak(host, 'userId')] = userId;
    }
    _prefs.setString(_key, jsonEncode(_data));
    notifyListeners();
  }

  /// Boolean UI section state (member sidebar, mature confirmation, collapsed categories ...).
  bool sectionState(String key, bool fallback) =>
      _get<bool>('layout.sections.$key', fallback);
  void setSectionState(String key, bool value) =>
      _set('layout.sections.$key', value);
  void toggleSectionState(String key, bool fallback) =>
      setSectionState(key, !sectionState(key, fallback));

  String get lastActivePath => _get('layout.lastActivePath', '/');
  set lastActivePath(String v) => _set('layout.lastActivePath', v);
  String? get nextPath => _get<String?>('layout.nextPath', null);
  set nextPath(String? v) => _set('layout.nextPath', v);
  String? get savedPush => _get<String?>('push.subscription', null);
  set savedPush(String? v) => _set('push.subscription', v);

  // --- link safety ---
  List<String> get trustedOrigins =>
      (_get<List>('linkSafety.savedOrigins', const [])).cast<String>();
  bool isTrusted(Uri u) => u.hasAuthority && trustedOrigins.contains(u.origin);
  void trustOrigin(Uri u) {
    if (!u.hasAuthority || trustedOrigins.contains(u.origin)) return;
    _set('linkSafety.savedOrigins', [...trustedOrigins, u.origin]);
  }

  // --- per-user voice settings ---
  double userVolume(String id) =>
      (_map('voice.userVolumes')[id] as num?)?.toDouble() ?? 1.0;
  void setUserVolume(String id, double v) {
    final m = _map('voice.userVolumes')..[id] = v;
    _set('voice.userVolumes', m);
  }

  bool userMuted(String id) => _map('voice.userMutes')[id] == true;
  void setUserMuted(String id, bool v) {
    final m = _map('voice.userMutes');
    v ? m[id] = true : m.remove(id);
    _set('voice.userMutes', m);
  }

  double screenShareVolume(String id) =>
      (_map('voice.screenShareVolumes')[id] as num?)?.toDouble() ?? 1.0;
  void setScreenShareVolume(String id, double v) {
    final m = _map('voice.screenShareVolumes')..[id] = v;
    _set('voice.screenShareVolumes', m);
  }

  bool screenShareMuted(String id) =>
      _map('voice.screenShareMutes')[id] == true;
  void setScreenShareMuted(String id, bool v) {
    final m = _map('voice.screenShareMutes');
    v ? m[id] = true : m.remove(id);
    _set('voice.screenShareMutes', m);
  }

  // --- per server/channel notification options ---
  Map<String, dynamic> _map(String k) =>
      Map<String, dynamic>.from(_get<Map>(k, {}));

  /// kind is 'server' or 'channel'; value is all | mention | none.
  String? notifFor(String kind, String id) =>
      _map('notif.$kind')[id] as String?;
  void setNotif(String kind, String id, String? v) {
    final m = _map('notif.$kind');
    v == null ? m.remove(id) : m[id] = v;
    _set('notif.$kind', m);
    touchSync('notifications');
  }

  /// Milliseconds since epoch; -1 means muted forever.
  int? mutedUntil(String kind, String id) =>
      (_map('mute.$kind')[id] as num?)?.toInt();
  void setMute(String kind, String id, int? until) {
    final m = _map('mute.$kind');
    until == null ? m.remove(id) : m[id] = until;
    _set('mute.$kind', m);
    touchSync('notifications');
  }

  bool isMuted(String kind, String id) {
    final u = mutedUntil(kind, id);
    return u != null && (u == -1 || u > DateTime.now().millisecondsSinceEpoch);
  }

  // --- raw access for stores kept in sync across devices ---
  T? raw<T>(String key) {
    final v = _data[key];
    return v is T ? v : null;
  }

  /// Writes a value; pass [syncKey] to queue the matching synced store for upload.
  void setRaw(String key, Object? value, {String? syncKey}) {
    _set(key, value);
    if (syncKey != null) touchSync(syncKey);
  }

  // --- cross-device sync (ordering, notifications, server folders, release notes) ---
  static const syncKeys = [
    'ordering',
    'notifications',
    'release-notes',
    'server-folders',
  ];
  final Set<String> syncQueue = {};
  void Function()? onSyncQueued;

  int revision(String key) =>
      (_map('sync.revision')[key] as num?)?.toInt() ?? 0;
  void _setRevision(String key, int ts) {
    final m = _map('sync.revision')..[key] = ts;
    _set('sync.revision', m);
  }

  void touchSync(String key) {
    _setRevision(key, DateTime.now().millisecondsSinceEpoch);
    syncQueue.add(key);
    onSyncQueued?.call();
  }

  /// Takes the queued keys, stamping them for upload.
  ({int ts, Map<String, String> payload}) takeSyncPayload() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final payload = {for (final k in syncQueue) k: exportSync(k)};
    for (final k in syncQueue) {
      _setRevision(k, ts);
    }
    syncQueue.clear();
    return (ts: ts, payload: payload);
  }

  String exportSync(String key) {
    switch (key) {
      case 'ordering':
        final sidebar = raw<List>('ordering.serverSidebar');
        return jsonEncode({
          'servers': raw<List>('ordering.servers') ?? const [],
          'serverSidebar': ?sidebar,
        });
      case 'server-folders':
        return jsonEncode({'folders': raw<List>('folders.list') ?? const []});
      case 'notifications':
        final now = DateTime.now().millisecondsSinceEpoch;
        Map<String, dynamic> mutes(String kind) => {
          for (final e in _map('mute.$kind').entries)
            if (e.value == -1 || (e.value as num) > now)
              e.key: e.value == -1 ? <String, dynamic>{} : {'until': e.value},
        };
        return jsonEncode({
          'server': _map('notif.server'),
          'channel': _map('notif.channel'),
          'server_mutes': mutes('server'),
          'channel_mutes': mutes('channel'),
        });
      default:
        return jsonEncode(
          raw<Map>('sync.releaseNotes') ?? {'lastSeenId': '', 'lastSeenAt': ''},
        );
    }
  }

  /// Merges remote data; newer remote revisions replace local, older ones trigger a re-upload.
  void importSync(String key, int ts, String data) {
    if (!syncKeys.contains(key)) return;
    Map<String, dynamic> parsed;
    try {
      parsed = (jsonDecode(data) as Map).cast<String, dynamic>();
    } catch (_) {
      return;
    }
    final local = revision(key);
    if (local == 0 || ts > local) {
      _setRevision(key, ts);
      switch (key) {
        case 'ordering':
          _set('ordering.servers', _stringList(parsed['servers']));
          _set(
            'ordering.serverSidebar',
            parsed['serverSidebar'] is List
                ? _stringList(parsed['serverSidebar'])
                : null,
          );
        case 'server-folders':
          _set(
            'folders.list',
            parsed['folders'] is List ? parsed['folders'] : <dynamic>[],
          );
        case 'notifications':
          final now = DateTime.now().millisecondsSinceEpoch;
          Map<String, dynamic> states(Object? m) => {
            for (final e in ((m as Map?) ?? const {}).entries)
              if (e.value is String) e.key as String: e.value,
          };
          Map<String, dynamic> mutes(Object? m) {
            final out = <String, dynamic>{};
            for (final e in ((m as Map?) ?? const {}).entries) {
              final v = e.value;
              if (v is! Map) continue;
              if (v['until'] == null) {
                out[e.key as String] = -1;
              } else if ((v['until'] as num) > now) {
                out[e.key as String] = v['until'];
              }
            }
            return out;
          }
          _set('notif.server', states(parsed['server']));
          _set('notif.channel', states(parsed['channel']));
          _set('mute.server', mutes(parsed['server_mutes']));
          _set('mute.channel', mutes(parsed['channel_mutes']));
        default:
          _set('sync.releaseNotes', parsed);
      }
    } else if (ts != local && exportSync(key) != jsonEncode(parsed)) {
      touchSync(key);
    }
  }

  static List<String> _stringList(Object? v) => [
    if (v is List)
      for (final e in v)
        if (e is String) e,
  ];
}
