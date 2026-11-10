import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;

import '../core/css_colour.dart';
import '../core/image_cache.dart';
import '../core/json.dart';
import '../core/links.dart';
import '../state/server_ordering.dart';
import '../state/settings_store.dart';
import 'api_client.dart';
import 'permissions.dart';
import 'transport.dart';

export '../core/json.dart';


enum LinkState { disconnected, connecting, connected, offline }

enum AuthState { unknown, loggedOut, loggedIn }

String _nonce() {
  const chars = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  final r = Random.secure();
  return List.generate(26, (_) => chars[r.nextInt(chars.length)]).join();
}

/// Holds all synced client state; the Dart equivalent of stoat.js `Client`.
class ClientStore extends ChangeNotifier {
  ClientStore(this.settings, {String? host}) {
    _setHost(host);
    settings.onSyncQueued = _scheduleSyncSave;
  }

  Timer? _syncTimer;

  /// Downloads rail icons and avatars of people you talk to in parallel.
  void _prefetchImages() {
    final urls = <String>[
      for (final s in servers.values) ?api.fileUrl('icons', s['icon'] as Map?, width: 256),
    ];
    final ids = <String>{
      for (final c in channels.values)
        if (c['channel_type'] == 'DirectMessage' || c['channel_type'] == 'Group') ...((c['recipients'] as List?) ?? const []).cast<String>(),
      ...users.values.where((u) => u['relationship'] == 'Friend').map((u) => u['_id'] as String),
    };
    for (final id in ids.take(200)) {
      final u = avatarUrl(id, size: 128);
      if (u != null) urls.add(u);
    }
    prefetchImages(urls);
  }

  void _scheduleSyncSave() {
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(seconds: 1), _saveSync);
  }

  Future<void> _initialSync() async {
    try {
      final res = await api.post('/sync/settings/fetch', {'keys': SettingsStore.syncKeys}) as Map;
      for (final e in res.entries) {
        final v = e.value as List;
        settings.importSync(e.key as String, (v[0] as num).toInt(), v[1] as String);
      }
      notifyListeners();
      if (settings.syncQueue.isNotEmpty) _scheduleSyncSave();
    } catch (_) {}
  }

  Future<void> _saveSync() async {
    if (api.token == null || settings.syncQueue.isEmpty) return;
    final p = settings.takeSyncPayload();
    try {
      await api.post('/sync/settings/set', {'timestamp': p.ts, ...p.payload});
    } catch (_) {
      settings.syncQueue.addAll(p.payload.keys);
    }
  }

  final SettingsStore settings;
  late ApiClient api;
  String? host;
  final GatewayConnection _gateway = GatewayConnection();
  StreamSubscription<GatewayMessage>? _gwSub;

  AuthState authState = AuthState.unknown;
  LinkState connection = LinkState.disconnected;
  bool ready = false;
  String? userId;

  final Map<String, Json> users = {};
  final Map<String, Json> servers = {};
  final Map<String, Json> channels = {};
  final Map<String, Map<String, Json>> members = {};
  final Map<String, Json> emojis = {};
  final Map<String, List<Json>> messages = {};
  final Map<String, Set<String>> typing = {};
  final Map<String, Json> unreads = {};
  final Map<String, Map<String, Json>> voiceStates = {};

  final _eventController = StreamController<Json>.broadcast();
  Stream<Json> get events => _eventController.stream;

  void _setHost(String? h) {
    host = h;
    final url = h == null || h == dawnchatHost ? dawnchatApiUrl : 'https://$h';
    api = ApiClient(url);
  }

  Future<void> switchHost(String? h) async {
    if (h == host) return;
    _teardown();
    _setHost(h);
    authState = AuthState.unknown;
    await init();
  }

  /// Loads instance config and resumes the stored session if any.
  Future<void> init() async {
    try {
      await api.fetchConfig();
    } catch (_) {
      connection = LinkState.offline;
      authState = AuthState.loggedOut;
      notifyListeners();
      return;
    }
    final token = settings.tokenFor(host);
    if (token != null) {
      api.token = token;
      userId = settings.userIdFor(host);
      authState = AuthState.loggedIn;
      notifyListeners();
      _connect();
    } else {
      authState = AuthState.loggedOut;
      notifyListeners();
    }
  }

  // ----- auth -----

  /// Returns null on success, or the MFA ticket map when a second factor is required.
  Future<Json?> login(String email, String password, {String? captcha}) async {
    final res = await api.post('/auth/session/login', {
      'email': email,
      'password': password,
      'friendly_name': 'DawnChat Flutter',
      'captcha': ?captcha,
    }) as Map;
    switch (res['result']) {
      case 'Success':
        await _completeLogin(res.cast<String, dynamic>());
        return null;
      case 'MFA':
        return res.cast<String, dynamic>();
      default:
        throw ApiException(403, 'AccountDisabled', res);
    }
  }

  Future<void> loginMfa(String ticket, Json response) async {
    final res = await api.post('/auth/session/login', {
      'mfa_ticket': ticket,
      'mfa_response': response,
      'friendly_name': 'DawnChat Flutter',
    }) as Map;
    await _completeLogin(res.cast<String, dynamic>());
  }

  Future<void> loginWithToken(String token) async {
    api.token = token;
    final me = await api.get('/users/@me') as Map;
    await _completeLogin({'token': token, '_id': '', 'user_id': me['_id']});
  }

  Future<void> _completeLogin(Json res) async {
    api.token = res['token'] as String;
    userId = res['user_id'] as String?;
    settings.setSession(host, api.token, res['_id'] as String?, userId);
    authState = AuthState.loggedIn;
    notifyListeners();
    _connect();
  }

  Future<void> logout() async {
    try {
      await api.post('/auth/session/logout');
    } catch (_) {}
    _teardown();
    settings.setSession(host, null, null, null);
    authState = AuthState.loggedOut;
    notifyListeners();
  }

  /// Notifies listeners after in-place mutation of cached maps.
  void refresh() => notifyListeners();

  void _teardown() {
    _gwSub?.cancel();
    _gateway.close();
    users.clear();
    servers.clear();
    channels.clear();
    members.clear();
    emojis.clear();
    messages.clear();
    typing.clear();
    unreads.clear();
    voiceStates.clear();
    ready = false;
    userId = null;
    api.token = null;
    connection = LinkState.disconnected;
  }

  // ----- gateway -----

  void _connect() {
    final cfg = api.config;
    if (cfg == null || api.token == null) return;
    connection = LinkState.connecting;
    notifyListeners();
    _gwSub?.cancel();
    _gwSub = _gateway.events.listen(_onGateway);
    _gateway.connect(
      '${cfg.ws}/?version=1&format=json&token=${Uri.encodeQueryComponent(api.token!)}',
    );
  }

  void _onGateway(GatewayMessage m) {
    if (m.isOpen) return;
    if (m.closedReason != null) {
      connection = LinkState.disconnected;
      notifyListeners();
      return;
    }
    Json event;
    try {
      event = (jsonDecode(m.text!) as Map).cast<String, dynamic>();
    } catch (_) {
      return;
    }
    _handle(event);
    _eventController.add(event);
  }

  void beginTyping(String channel) =>
      _gateway.send({'type': 'BeginTyping', 'channel': channel});
  void endTyping(String channel) =>
      _gateway.send({'type': 'EndTyping', 'channel': channel});

  void _handle(Json e) {
    switch (e['type']) {
      case 'Ready':
        for (final u in (e['users'] as List? ?? [])) {
          users[u['_id']] = (u as Map).cast<String, dynamic>();
        }
        for (final s in (e['servers'] as List? ?? [])) {
          servers[s['_id']] = (s as Map).cast<String, dynamic>();
        }
        for (final c in (e['channels'] as List? ?? [])) {
          channels[c['_id']] = (c as Map).cast<String, dynamic>();
        }
        for (final m in (e['members'] as List? ?? [])) {
          final id = m['_id'] as Map;
          (members[id['server']] ??= {})[id['user']] = (m as Map)
              .cast<String, dynamic>();
        }
        for (final em in (e['emojis'] as List? ?? [])) {
          emojis[em['_id']] = (em as Map).cast<String, dynamic>();
        }
        for (final vs in (e['voice_states'] as List? ?? [])) {
          final m = (voiceStates[vs['id']] ??= {});
          for (final p in (vs['participants'] as List? ?? [])) {
            m[p['id']] = (p as Map).cast<String, dynamic>();
          }
        }
        ready = true;
        connection = LinkState.connected;
        _loadUnreads();
        _initialSync();
        _prefetchImages();
      case 'UserSettingsUpdate':
        for (final entry in ((e['update'] as Map?) ?? const {}).entries) {
          final v = entry.value;
          if (v is List && v.length >= 2) settings.importSync(entry.key as String, (v[0] as num).toInt(), v[1] as String);
        }
      case 'Message':
        final ch = e['channel'] as String;
        final list = messages[ch];
        if (list != null && !detached.contains(ch) && !list.any((x) => x['_id'] == e['_id'])) {
          list.removeWhere(
            (x) => x['nonce'] != null && x['nonce'] == e['nonce'],
          );
          list.add(e);
        }
        channels[ch]?['last_message_id'] = e['_id'];
        if (e['author'] != userId) _markUnread(ch, e);
        typing[ch]?.remove(e['author']);
      case 'MessageUpdate':
        final list = messages[e['channel']];
        final i = list?.indexWhere((x) => x['_id'] == e['id']) ?? -1;
        if (i >= 0) {
          list![i] = {
            ...list[i],
            ...(e['data'] as Map).cast<String, dynamic>(),
          };
        }
      case 'MessageDelete':
        messages[e['channel']]?.removeWhere((x) => x['_id'] == e['id']);
      case 'MessageReact':
        _react(e, true);
      case 'MessageUnreact':
        _react(e, false);
      case 'ChannelCreate':
        channels[e['_id']] = e;
      case 'ChannelUpdate':
        final c = channels[e['id']];
        if (c != null) {
          c.addAll((e['data'] as Map).cast<String, dynamic>());
          for (final k in (e['clear'] as List? ?? [])) {
            c.remove(_clearKey(k as String));
          }
        }
      case 'ChannelDelete':
        channels.remove(e['id']);
      case 'ChannelStartTyping':
        (typing[e['id']] ??= {}).add(e['user']);
      case 'ChannelStopTyping':
        typing[e['id']]?.remove(e['user']);
      case 'ChannelAck':
        if (e['user'] == userId) {
          unreads.remove(e['id']);
        }
      case 'ServerCreate':
        servers[e['id']] = (e['server'] as Map).cast<String, dynamic>();
        for (final c in (e['channels'] as List? ?? [])) {
          channels[c['_id']] = (c as Map).cast<String, dynamic>();
        }
      case 'ServerUpdate':
        final s = servers[e['id']];
        if (s != null) {
          s.addAll((e['data'] as Map).cast<String, dynamic>());
          for (final k in (e['clear'] as List? ?? [])) {
            s.remove(_clearKey(k as String));
          }
        }
      case 'ServerDelete':
        servers.remove(e['id']);
        channels.removeWhere((_, c) => c['server'] == e['id']);
        members.remove(e['id']);
      case 'ServerMemberJoin':
        loadMembers(e['id'] as String);
      case 'ServerMemberLeave':
        members[e['id']]?.remove(e['user']);
      case 'UserUpdate':
        final u = users[e['id']];
        if (u != null) {
          u.addAll((e['data'] as Map).cast<String, dynamic>());
          for (final k in (e['clear'] as List? ?? [])) {
            u.remove(_clearKey(k as String));
          }
        }
      case 'UserRelationship':
        final u = (e['user'] as Map).cast<String, dynamic>();
        users[u['_id']] = {
          ...?users[u['_id']],
          ...u,
          'relationship': e['status'],
        };
      case 'VoiceChannelJoin':
        (voiceStates[e['id']] ??= {})[e['state']['id']] = (e['state'] as Map)
            .cast<String, dynamic>();
      case 'VoiceChannelLeave':
        voiceStates[e['id']]?.remove(e['user']);
      case 'UserVoiceStateUpdate':
        final st = voiceStates[e['channel_id']]?[e['id']];
        if (st != null) st.addAll((e['data'] as Map).cast<String, dynamic>());
      case 'VoiceChannelMove':
        voiceStates[e['from']]?.remove(e['user']);
        (voiceStates[e['to']] ??= {})[e['user']] =
            (e['state'] as Map).cast<String, dynamic>();
      case 'ChannelGroupJoin':
        final rec = channels[e['id']]?['recipients'] as List?;
        if (rec != null && !rec.contains(e['user'])) rec.add(e['user']);
      case 'ChannelGroupLeave':
        (channels[e['id']]?['recipients'] as List?)?.remove(e['user']);
      case 'ServerMemberUpdate':
        final mid = e['id'] as Map;
        final mem = members[mid['server']]?[mid['user']];
        if (mem != null) {
          mem.addAll((e['data'] as Map).cast<String, dynamic>());
          for (final k in (e['clear'] as List? ?? [])) {
            mem.remove(_clearKey(k as String));
          }
        }
      case 'ServerRoleUpdate':
        final roles = (servers[e['id']]?['roles'] ??= <String, dynamic>{}) as Map;
        final role = (roles[e['role_id']] ??= <String, dynamic>{}) as Map;
        role.addAll((e['data'] as Map).cast<String, dynamic>());
      case 'ServerRoleDelete':
        (servers[e['id']]?['roles'] as Map?)?.remove(e['role_id']);
      case 'EmojiCreate':
        emojis[e['_id']] = e;
      case 'EmojiDelete':
        emojis.remove(e['id']);
      case 'MessageAppend':
        final list = messages[e['channel']];
        final i = list?.indexWhere((x) => x['_id'] == e['id']) ?? -1;
        if (i >= 0) {
          final emb = [...(list![i]['embeds'] as List? ?? []), ...((e['append'] as Map?)?['embeds'] as List? ?? [])];
          list[i] = {...list[i], 'embeds': emb};
        }
      case 'BulkMessageDelete':
        final ids = (e['ids'] as List).toSet();
        messages[e['channel']]?.removeWhere((x) => ids.contains(x['_id']));
      case 'Logout':
        logout();
        return;
    }
    notifyListeners();
  }

  String _clearKey(String k) => switch (k) {
    'Avatar' => 'avatar',
    'Icon' => 'icon',
    'Banner' => 'banner',
    'Description' => 'description',
    'StatusText' => 'status',
    'ProfileContent' => 'profile',
    'ProfileBackground' => 'profile',
    'DisplayName' => 'display_name',
    _ => k.toLowerCase(),
  };

  void _react(Json e, bool add) {
    final list = messages[e['channel_id']];
    final i = list?.indexWhere((x) => x['_id'] == e['id']) ?? -1;
    if (i < 0) return;
    final msg = Json.of(list![i]);
    final reactions = Json.of(
      (msg['reactions'] as Map?)?.cast<String, dynamic>() ?? {},
    );
    final users = List<String>.from(reactions[e['emoji_id']] as List? ?? []);
    if (add) {
      if (!users.contains(e['user_id'])) users.add(e['user_id']);
    } else {
      users.remove(e['user_id']);
    }
    if (users.isEmpty) {
      reactions.remove(e['emoji_id']);
    } else {
      reactions[e['emoji_id']] = users;
    }
    msg['reactions'] = reactions;
    list[i] = msg;
  }

  // ----- unreads -----

  Future<void> _loadUnreads() async {
    try {
      final res = await api.get('/sync/unreads') as List;
      for (final u in res) {
        unreads[u['_id']['channel']] = (u as Map).cast<String, dynamic>();
      }
      notifyListeners();
    } catch (_) {}
  }

  void _markUnread(String ch, Json msg) {
    final mentioned = (msg['mentions'] as List?)?.contains(userId) ?? false;
    final u = unreads[ch] ??= {
      '_id': {'channel': ch, 'user': userId},
      'last_id': null,
      'mentions': <dynamic>[],
    };
    u['unread'] = true;
    if (mentioned) (u['mentions'] as List).add(msg['_id']);
  }

  bool isMuted(String channel) {
    final c = channels[channel];
    if (c == null) return false;
    if (settings.isMuted('channel', channel)) return true;
    final s = c['server'] as String?;
    return s != null && settings.isMuted('server', s);
  }

  /// Effective notification level: all | mention | none.
  String notifyLevel(String channel) {
    final c = channels[channel];
    final own = settings.notifFor('channel', channel);
    if (own != null) return own;
    final s = c?['server'] as String?;
    if (s != null) return settings.notifFor('server', s) ?? 'mention';
    return 'all';
  }

  bool isUnread(String channel) {
    final c = channels[channel];
    if (c == null || isMuted(channel)) return false;
    final last = c['last_message_id'] as String?;
    if (last == null) return false;
    final u = unreads[channel];
    if (u == null) return false;
    if (u['unread'] == true) return true;
    final seen = u['last_id'] as String?;
    return seen == null || seen.compareTo(last) < 0;
  }

  int mentionCount(String channel) =>
      (unreads[channel]?['mentions'] as List?)?.length ?? 0;

  Future<void> ack(String channel, String messageId) async {
    unreads.remove(channel);
    notifyListeners();
    try {
      await api.put('/channels/$channel/ack/$messageId');
    } catch (_) {}
  }

  // ----- data access -----

  Json? get me => users[userId];

  /// Server roles a member holds, highest ranked first.
  List<Json> memberRoles(String? serverId, String? userId) {
    if (serverId == null || userId == null) return const [];
    final roles = (servers[serverId]?['roles'] as Map?)?.cast<String, dynamic>() ?? const {};
    final mine = ((members[serverId]?[userId]?['roles'] as List?) ?? const []).cast<String>();
    final out = [
      for (final r in mine)
        if (roles[r] != null) {...(roles[r] as Map).cast<String, dynamic>(), '_id': r},
    ]..sort((a, b) => ((a['rank'] as num?) ?? 0).compareTo((b['rank'] as num?) ?? 0));
    return out;
  }

  /// Lower is more powerful; the owner outranks everyone.
  double memberRank(String? serverId, String? userId) {
    if (serverId == null) return double.infinity;
    if (servers[serverId]?['owner'] == userId) return double.negativeInfinity;
    final roles = memberRoles(serverId, userId);
    return roles.isEmpty ? double.infinity : ((roles.first['rank'] as num?) ?? 0).toDouble();
  }

  /// Whether [userId] ranks below the current user in [serverId].
  bool inferiorToMe(String serverId, String userId) => memberRank(serverId, userId) > memberRank(serverId, this.userId);

  /// Server-level permission check for the current user (ignores channel overrides).
  bool canInServer(String serverId, BigInt perm) {
    final s = servers[serverId];
    if (s == null || userId == null) return false;
    if (s['owner'] == userId) return true;
    final p = serverPermissions(server: s, member: members[serverId]?[userId]);
    return (p & perm) == perm;
  }

  /// Colour of the member's highest-ranked coloured role.
  Color? roleColour(String? userId, String? serverId) {
    if (userId == null || serverId == null) return null;
    final roles = (servers[serverId]?['roles'] as Map?)?.cast<String, dynamic>();
    final mine = ((members[serverId]?[userId]?['roles'] as List?) ?? const []).cast<String>();
    if (roles == null || mine.isEmpty) return null;
    final ranked = mine.where((r) => roles[r]?['colour'] != null).toList()
      ..sort((a, b) => ((roles[a]['rank'] as num?) ?? 0).compareTo((roles[b]['rank'] as num?) ?? 0));
    return ranked.isEmpty ? null : parseCssColour(roles[ranked.first]['colour'] as String?);
  }

  /// Server icon role (`iconRole`) of the member's top role, if any.
  Map<String, dynamic>? iconRole(String? userId, String? serverId) {
    if (userId == null || serverId == null) return null;
    final roles = (servers[serverId]?['roles'] as Map?)?.cast<String, dynamic>();
    final mine = ((members[serverId]?[userId]?['roles'] as List?) ?? const []).cast<String>();
    if (roles == null) return null;
    final withIcon = mine.where((r) => roles[r]?['icon'] != null).toList()
      ..sort((a, b) => ((roles[a]['rank'] as num?) ?? 0).compareTo((roles[b]['rank'] as num?) ?? 0));
    return withIcon.isEmpty ? null : (roles[withIcon.first] as Map).cast<String, dynamic>();
  }

  /// Whether the current user holds a permission in a channel.
  bool can(String channelId, BigInt perm) {
    final c = channels[channelId];
    if (c == null || userId == null) return false;
    final sid = c['server'] as String?;
    final p = channelPermissions(
      channel: c,
      server: sid == null ? null : servers[sid],
      member: sid == null ? null : members[sid]?[userId],
      userId: userId!,
    );
    return (p & perm) == perm;
  }

  bool canAny(String channelId, List<BigInt> perms) => perms.any((p) => can(channelId, p));

  /// Channels that support calls: voice-enabled text channels, legacy voice channels, DMs and groups.
  bool isVoice(Json c) =>
      c['voice'] != null ||
      c['channel_type'] == 'VoiceChannel' ||
      c['channel_type'] == 'DirectMessage' ||
      c['channel_type'] == 'Group';

  Json? user(String? id) => id == null ? null : users[id];

  String displayName(String? id, {String? server}) {
    final u = users[id];
    if (u == null) return 'Unknown User';
    final m = server == null ? null : members[server]?[id];
    final nick = m?['nickname'] as String?;
    return nick ??
        (u['display_name'] as String?) ??
        (u['username'] as String? ?? 'Unknown');
  }

  String? avatarUrl(String? id, {double size = 64}) {
    final u = users[id];
    if (u == null || id == null) return null;
    return api.fileUrl(
          'avatars',
          u['avatar'] as Map?,
          width: (size * 3).round().clamp(128, 512),
        ) ??
        api.defaultAvatar(id);
  }

  List<Json> get serverList => [
    for (final id in ServerOrdering(settings).orderedServers(servers.keys)) servers[id]!,
  ];

  ServerOrdering get ordering => ServerOrdering(settings);

  List<Json> channelsOfServer(String serverId) {
    final s = servers[serverId];
    final ids = (s?['channels'] as List?)?.cast<String>() ?? [];
    return ids.map((i) => channels[i]).whereType<Json>().toList();
  }

  List<Json> get dmList {
    final list = channels.values
        .where(
          (c) =>
              c['channel_type'] == 'DirectMessage' ||
              c['channel_type'] == 'Group',
        )
        .where((c) => c['active'] != false)
        .toList();
    list.sort((a, b) {
      final x = (a['last_message_id'] as String?) ?? a['_id'] as String;
      final y = (b['last_message_id'] as String?) ?? b['_id'] as String;
      return y.compareTo(x);
    });
    return list;
  }

  String channelName(Json c) {
    switch (c['channel_type']) {
      case 'SavedMessages':
        return 'Saved Notes';
      case 'DirectMessage':
        final other = (c['recipients'] as List).cast<String>().firstWhere(
          (r) => r != userId,
          orElse: () => userId ?? '',
        );
        return displayName(other);
      default:
        return (c['name'] as String?) ?? 'Unnamed';
    }
  }

  List<Json> get friends =>
      users.values.where((u) => u['relationship'] == 'Friend').toList();
  List<Json> get incomingRequests =>
      users.values.where((u) => u['relationship'] == 'Incoming').toList();
  List<Json> get outgoingRequests =>
      users.values.where((u) => u['relationship'] == 'Outgoing').toList();
  List<Json> get blocked =>
      users.values.where((u) => u['relationship'] == 'Blocked').toList();

  // ----- messages -----

  /// Messages fetched individually (reply targets) that are not part of a channel list.
  final Map<String, Json> fetchedMessages = {};
  final Set<String> _fetching = {};

  /// Channels whose loaded list does not reach the newest message.
  final Set<String> detached = {};

  Json? messageById(String channel, String id) {
    final list = messages[channel];
    if (list != null) {
      for (final m in list) {
        if (m['_id'] == id) return m;
      }
    }
    return fetchedMessages[id];
  }

  Future<void> fetchMessage(String channel, String id) async {
    if (fetchedMessages.containsKey(id) || !_fetching.add(id)) return;
    try {
      final m = (await api.get('/channels/$channel/messages/$id') as Map).cast<String, dynamic>();
      fetchedMessages[id] = m;
      if (users[m['author']] == null) {
        try {
          await fetchUser(m['author'] as String);
        } catch (_) {}
      }
      notifyListeners();
    } catch (_) {
    } finally {
      _fetching.remove(id);
    }
  }

  /// Loads a page of messages. [replace] swaps the list (used for jumps) instead of merging.
  Future<List<Json>> loadMessages(
    String channel, {
    String? before,
    String? after,
    String? nearby,
    int limit = 50,
    bool replace = false,
  }) async {
    final res = await api.get(
      '/channels/$channel/messages',
      query: {
        'limit': limit,
        'include_users': true,
        if (after != null) 'sort': 'Oldest',
        'after': ?after,
        'nearby': ?nearby,
        'before': ?before,
      },
    ) as Map;
    final msgs = (res['messages'] as List)
        .cast<Map>()
        .map((m) => m.cast<String, dynamic>())
        .toList();
    for (final u in (res['users'] as List? ?? [])) {
      users[u['_id']] = {
        ...?users[u['_id']],
        ...(u as Map).cast<String, dynamic>(),
      };
    }
    for (final m in (res['members'] as List? ?? [])) {
      final id = m['_id'] as Map;
      (members[id['server']] ??= {})[id['user']] = (m as Map)
          .cast<String, dynamic>();
    }
    final list = messages[channel] ??= [];
    if (replace) list.removeWhere((m) => m['pending'] != true && m['failed'] != true);
    final ids = list.map((m) => m['_id']).toSet();
    list.addAll(msgs.where((m) => !ids.contains(m['_id'])));
    list.sort((a, b) => (a['_id'] as String).compareTo(b['_id'] as String));
    final last = channels[channel]?['last_message_id'];
    if (replace || nearby != null) {
      if (last == null || list.any((m) => m['_id'] == last)) {
        detached.remove(channel);
      } else {
        detached.add(channel);
      }
    } else if (after != null && msgs.length < limit) {
      detached.remove(channel);
    }
    notifyListeners();
    return msgs;
  }

  Future<void> sendMessage(
    String channel,
    String content, {
    List<String> attachments = const [],
    List<Json> replies = const [],
  }) async {
    final nonce = _nonce();
    final pending = <String, dynamic>{
      '_id': nonce,
      'nonce': nonce,
      'channel': channel,
      'author': userId,
      'content': content,
      'pending': true,
      '_attachments': attachments,
      '_replies': replies,
      if (replies.isNotEmpty) 'replies': replies.map((r) => r['id']).toList(),
    };
    (messages[channel] ??= []).add(pending);
    notifyListeners();
    try {
      final res = await api.request(
        'POST',
        '/channels/$channel/messages',
        headers: {'Idempotency-Key': nonce},
        body: {
          'content': content,
          if (attachments.isNotEmpty) 'attachments': attachments,
          if (replies.isNotEmpty) 'replies': replies,
        },
      ) as Map;
      final list = messages[channel]!;
      final i = list.indexWhere((m) => m['nonce'] == nonce);
      if (i >= 0) {
        list[i] = (res).cast<String, dynamic>();
      } else if (!list.any((m) => m['_id'] == res['_id'])) {
        list.add(res.cast<String, dynamic>());
      }
      final slow = (channels[channel]?['slowmode'] as num?)?.toInt() ?? 0;
      if (slow > 0 && !can(channel, Perm.bypassSlowmode)) {
        slowmodeUntil[channel] = DateTime.now().add(Duration(seconds: slow));
      }
      notifyListeners();
    } catch (e) {
      if (e is ApiException && e.status == 429 && e.body is Map && (e.body as Map)['retry_after'] is num) {
        slowmodeUntil[channel] = DateTime.now().add(Duration(milliseconds: ((e.body as Map)['retry_after'] as num).toInt() * 1000));
      }
      pending['failed'] = true;
      pending.remove('pending');
      notifyListeners();
      rethrow;
    }
  }

  /// Slowmode cooldown end per channel (set locally after sends / 429 responses).
  final Map<String, DateTime> slowmodeUntil = {};

  Future<void> editMessage(String channel, String id, String content) =>
      api.patch('/channels/$channel/messages/$id', {'content': content});

  void discardMessage(String channel, String nonce) {
    messages[channel]?.removeWhere((m) => m['nonce'] == nonce);
    notifyListeners();
  }

  Future<void> retryMessage(String channel, Json failed) async {
    discardMessage(channel, failed['nonce'] as String);
    await sendMessage(
      channel,
      failed['content'] as String? ?? '',
      attachments: (failed['_attachments'] as List?)?.cast<String>() ?? const [],
      replies: (failed['_replies'] as List?)?.cast<Json>() ?? const [],
    );
  }

  Future<void> deleteMessage(String channel, String id) =>
      api.delete('/channels/$channel/messages/$id');

  Future<void> pinMessage(String channel, String id) => api.post('/channels/$channel/messages/$id/pin');

  /// Searches a channel (query text or pinned) and merges returned users/members.
  Future<List<Json>> searchMessages(String channel, {String? query, bool pinned = false, String sort = 'Latest'}) async {
    final res = await api.post('/channels/$channel/search', {
      'query': ?query,
      if (pinned) 'pinned': true,
      'sort': sort,
      'limit': 50,
      'include_users': true,
    }) as Map;
    for (final u in (res['users'] as List? ?? [])) {
      users[u['_id']] = {...?users[u['_id']], ...(u as Map).cast<String, dynamic>()};
    }
    for (final m in (res['members'] as List? ?? [])) {
      final id = m['_id'] as Map;
      (members[id['server']] ??= {})[id['user']] = (m as Map).cast<String, dynamic>();
    }
    notifyListeners();
    return [for (final m in (res['messages'] as List)) (m as Map).cast<String, dynamic>()];
  }
  Future<void> unpinMessage(String channel, String id) => api.delete('/channels/$channel/messages/$id/pin');

  Future<void> clearReactions(String channel, String id) =>
      api.delete('/channels/$channel/messages/$id/reactions');

  /// Removes one emoji for every user (needs ManageMessages).
  Future<void> removeReactionForAll(String channel, String id, String emoji) =>
      api.delete('/channels/$channel/messages/$id/reactions/${Uri.encodeComponent(emoji)}?remove_all=true');

  /// Marks a message and everything after it as unread.
  Future<void> markUnreadFrom(String channel, String id) async {
    final list = messages[channel] ?? const [];
    final i = list.indexWhere((m) => m['_id'] == id);
    final prev = i > 0 ? list[i - 1]['_id'] as String : null;
    unreads[channel] = {
      '_id': {'channel': channel, 'user': userId},
      'last_id': prev,
      'mentions': <dynamic>[],
    };
    notifyListeners();
    if (prev != null) {
      try {
        await api.put('/channels/$channel/ack/$prev');
        unreads[channel]!['last_id'] = prev;
        notifyListeners();
      } catch (_) {}
    }
  }

  Future<void> react(String channel, String id, String emoji, bool add) => add
      ? api.put(
          '/channels/$channel/messages/$id/reactions/${Uri.encodeComponent(emoji)}',
        )
      : api.delete(
          '/channels/$channel/messages/$id/reactions/${Uri.encodeComponent(emoji)}',
        );

  // ----- servers / members / social -----

  Future<void> loadMembers(String serverId) async {
    final res = await api.get(
      '/servers/$serverId/members',
      query: {'exclude_offline': false},
    ) as Map;
    final map = members[serverId] ??= {};
    for (final m in (res['members'] as List)) {
      map[(m['_id'] as Map)['user']] = (m as Map).cast<String, dynamic>();
    }
    for (final u in (res['users'] as List)) {
      users[u['_id']] = {
        ...?users[u['_id']],
        ...(u as Map).cast<String, dynamic>(),
      };
    }
    notifyListeners();
  }

  Future<Json> fetchUser(String id) async {
    final u = ((await api.get('/users/$id')) as Map).cast<String, dynamic>();
    users[id] = {...?users[id], ...u};
    notifyListeners();
    return u;
  }

  Future<Json> openDm(String userId) async {
    final c = ((await api.get('/users/$userId/dm')) as Map)
        .cast<String, dynamic>();
    channels[c['_id']] = c;
    notifyListeners();
    return c;
  }

  Future<void> addFriend(String username) async {
    await api.post('/users/friend', {'username': username});
  }

  Future<void> acceptFriend(String id) async {
    await api.put('/users/$id/friend');
  }

  Future<void> removeFriend(String id) async {
    await api.delete('/users/$id/friend');
  }

  Future<void> blockUser(String id) async {
    await api.put('/users/$id/block');
  }

  Future<void> unblockUser(String id) async {
    await api.delete('/users/$id/block');
  }

  Future<void> setStatus(String presence, {String? text, bool clearText = false}) async {
    await api.patch('/users/@me', {
      'status': {'presence': presence, 'text': ?text},
      if (clearText) 'remove': ['StatusText'],
    });
  }

  Future<Json> joinInvite(String code) async {
    return ((await api.post('/invites/$code')) as Map).cast<String, dynamic>();
  }

  Future<Json> fetchInvite(String code) async =>
      ((await api.get('/invites/$code')) as Map).cast<String, dynamic>();

  Future<Json> createServer(String name) async => ((await api.post(
    '/servers/create',
    {'name': name, 'nonce': _nonce()},
  )) as Map).cast<String, dynamic>();

  Future<void> leaveServer(String id) async {
    await api.delete('/servers/$id');
  }

  Future<List<Json>> sessions() async =>
      ((await api.get('/auth/session/all')) as List)
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();

  Future<void> revokeSession(String id) async {
    await api.delete('/auth/session/$id');
  }

  Future<void> revokeAllSessions() async {
    await api.delete('/auth/session/all');
  }

  Future<List<Json>> myBots() async {
    final res = await api.get('/bots/@me') as Map;
    for (final u in (res['users'] as List)) {
      users[u['_id']] = (u as Map).cast<String, dynamic>();
    }
    return (res['bots'] as List)
        .map((b) => (b as Map).cast<String, dynamic>())
        .toList();
  }

  // ----- voice -----

  /// Requests a LiveKit token for the channel.
  Future<({String url, String token})> joinCall(
    String channel, {
    String? node,
  }) async {
    final res = await api.post('/channels/$channel/join_call', {
      'node': ?node,
    }) as Map;
    return (url: res['url'] as String, token: res['token'] as String);
  }

  @override
  void dispose() {
    _gwSub?.cancel();
    _gateway.close();
    _eventController.close();
    super.dispose();
  }
}
