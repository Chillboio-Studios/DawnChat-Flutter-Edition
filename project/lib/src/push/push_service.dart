import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../api/client_store.dart';
import '../core/i18n.dart';
import '../rust/api/push.dart' as rust_push;
import '../state/settings_store.dart';
import '../ui/widgets.dart';
import '../voice/voice_manager.dart';
import 'web_push_stub.dart'
    if (dart.library.js_interop) 'web_push.dart'
    as web_push;

/// Firebase project values are injected at build time (`--dart-define`) so no secret files are committed.
class FirebaseConfig {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const messagingSenderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static bool get configured =>
      apiKey.isNotEmpty && appId.isNotEmpty && projectId.isNotEmpty;

  static FirebaseOptions get options => const FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: messagingSenderId,
    projectId: projectId,
  );
}

@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  // The OS displays notification payloads while the app is in the background.
}

bool get _isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
bool get _isApple =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);
bool get _isDesktopPush =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows);

/// Push + local notifications for every platform:
/// Android: FCM, iOS/macOS: APNs token via Firebase, web: VAPID web push,
/// Windows/Linux: Rust Web Push client (autopush) while the app runs in tray/background.
class PushService extends ChangeNotifier {
  PushService(this.store, this.settings);

  final ClientStore store;
  final SettingsStore settings;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  StreamSubscription<Json>? _events;
  StreamSubscription<dynamic>? _rustSub;
  StreamSubscription<String>? _tokenSub;
  bool _localReady = false;
  bool _firebaseReady = false;
  bool _started = false;
  bool appInForeground = true;
  SoundService? sounds;
  String? activeChannel;
  int _nid = 1;

  bool get desktopSupported => true;

  Future<void> init() async {
    if (_started) return;
    _started = true;
    await _initLocal();
    _events = store.events.listen(_onGatewayEvent);
    store.addListener(_onStoreChanged);
  }

  void _onStoreChanged() {
    if (store.ready && store.authState == AuthState.loggedIn) {
      _afterLogin();
    }
  }

  bool _didLogin = false;
  void _afterLogin() {
    if (_didLogin) return;
    _didLogin = true;
    final s = settings.pushNotifications;
    if (s == 'default' || s == 'allowed') {
      enablePush(requestPermission: s == 'default');
    }
  }

  Future<void> _initLocal() async {
    try {
      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
          macOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
          linux: LinuxInitializationSettings(
            defaultActionName: 'Open DawnChat',
          ),
          windows: WindowsInitializationSettings(
            appName: 'DawnChat',
            appUserModelId: 'com.dawnchat.app',
            guid: 'c3f6b7e4-1d5a-4a39-9e2b-6d2b1f5a8c10',
          ),
        ),
      );
      _localReady = true;
    } catch (e) {
      debugPrint('Local notifications unavailable: $e');
    }
  }

  // ---- permission toggles used by the settings page ----

  Future<void> toggleDesktop(BuildContext context) async {
    if (settings.desktopNotifications != 'allowed') {
      if (await _requestLocalPermission()) {
        settings.desktopNotifications = 'allowed';
      } else {
        settings.desktopNotifications = 'denied';
        if (context.mounted) {
          showSnack(
            context,
            tr(
              'Failed to enable notifications. DawnChat does not have notification permission.',
            ),
          );
        }
      }
    } else {
      settings.desktopNotifications = 'denied';
    }
  }

  Future<void> togglePush(BuildContext context) async {
    if (settings.pushNotifications != 'allowed') {
      final ok = await enablePush(requestPermission: true);
      if (!ok && context.mounted) {
        showSnack(
          context,
          tr('Failed to enable push notifications. Please try again later.'),
        );
      }
    } else {
      await disablePush();
    }
  }

  Future<bool> _requestLocalPermission() async {
    if (kIsWeb) return web_push.requestPermission();
    if (_isAndroid) {
      return await _local
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          true;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return await _local
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return await _local
              .resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    return true;
  }

  // ---- push subscription ----

  Future<bool> enablePush({bool requestPermission = false}) async {
    try {
      if (requestPermission && !await _requestLocalPermission()) {
        settings.pushNotifications = 'denied';
        return false;
      }
      if (settings.desktopNotifications == 'default') {
        settings.desktopNotifications = 'allowed';
      }

      if (kIsWeb) {
        final vapid = store.api.config?.vapid ?? '';
        final sub = await web_push.subscribe(vapid);
        if (sub == null) throw 'Web push is not supported in this browser';
        await store.api.post('/push/subscribe', sub);
      } else if (_isAndroid || _isApple) {
        await _enableFirebase();
      } else if (_isDesktopPush) {
        await _enableDesktopPush();
      }
      settings.pushNotifications = 'allowed';
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Push registration failed: $e');
      settings.pushNotifications = 'default';
      notifyListeners();
      return false;
    }
  }

  Future<void> disablePush() async {
    settings.pushNotifications = 'denied';
    try {
      await _tokenSub?.cancel();
      _tokenSub = null;
      await _rustSub?.cancel();
      _rustSub = null;
      if (_isDesktopPush) await rust_push.pushStop();
      if (kIsWeb) await web_push.unsubscribe();
      await store.api.post('/push/unsubscribe');
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _enableFirebase() async {
    if (!FirebaseConfig.configured) {
      throw 'Firebase is not configured (FIREBASE_* dart-defines)';
    }
    if (!_firebaseReady) {
      await Firebase.initializeApp(options: FirebaseConfig.options);
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
      FirebaseMessaging.onMessage.listen((m) {
        final n = m.notification;
        if (n != null && !appInForeground) {
          _show(
            n.title ?? 'DawnChat',
            n.body ?? '',
            payload: m.data['url'] as String?,
          );
        }
      });
      _firebaseReady = true;
    }
    final fm = FirebaseMessaging.instance;
    await fm.requestPermission();

    Future<void> register(String token, String endpoint) => store.api.post(
      '/push/subscribe',
      {'endpoint': endpoint, 'p256dh': '', 'auth': token},
    );

    if (_isAndroid) {
      final token = await fm.getToken();
      if (token == null) throw 'No FCM token available';
      await register(token, 'fcm');
      await _tokenSub?.cancel();
      _tokenSub = fm.onTokenRefresh.listen((t) {
        if (settings.pushNotifications == 'allowed') register(t, 'fcm');
      });
    } else {
      final apns = await fm.getAPNSToken();
      if (apns == null) throw 'No APNs token available';
      await register(apns, 'apn');
    }
  }

  Future<void> _enableDesktopPush() async {
    final vapid = store.api.config?.vapid ?? '';
    rust_push.PushSubscription? saved;
    final raw = settings.savedPush;
    if (raw != null) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        saved = rust_push.PushSubscription(
          endpoint: m['endpoint'] as String,
          p256Dh: m['p256dh'] as String,
          auth: m['auth'] as String,
          privateKey: m['private_key'] as String,
          uaid: m['uaid'] as String,
          channelId: m['channel_id'] as String,
        );
      } catch (_) {}
    }
    final done = Completer<void>();
    await _rustSub?.cancel();
    _rustSub = rust_push.pushStart(vapidKey: vapid, saved: saved).listen((
      e,
    ) async {
      switch (e) {
        case rust_push.PushEvent_Registered(:final field0):
          settings.savedPush = jsonEncode({
            'endpoint': field0.endpoint,
            'p256dh': field0.p256Dh,
            'auth': field0.auth,
            'private_key': field0.privateKey,
            'uaid': field0.uaid,
            'channel_id': field0.channelId,
          });
          try {
            await store.api.post('/push/subscribe', {
              'endpoint': field0.endpoint,
              'p256dh': field0.p256Dh,
              'auth': field0.auth,
            });
            if (!done.isCompleted) done.complete();
          } catch (err) {
            if (!done.isCompleted) done.completeError(err);
          }
        case rust_push.PushEvent_Notification(:final field0):
          _showFromPayload(field0);
        case rust_push.PushEvent_Closed():
          break;
      }
    });
    await done.future.timeout(const Duration(seconds: 20));
  }

  // ---- showing notifications ----

  void _showFromPayload(String json) {
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      final ch = m['channel'] as Map<String, dynamic>?;
      final title =
          (m['title'] as String?) ??
          (ch == null
              ? 'DawnChat'
              : ch['channel_type'] == 'DirectMessage'
              ? ((m['author'] as String?) ?? 'DawnChat')
              : '${m['author']} in ${ch['name']}');
      _show(title, (m['body'] ?? '') as String, payload: m['url'] as String?);
    } catch (_) {
      _show('DawnChat', json);
    }
  }

  void _onGatewayEvent(Json e) {
    if (e['type'] != 'Message') return;
    if (settings.desktopNotifications != 'allowed') return;
    final channel = e['channel'] as String;
    if (e['author'] == store.userId) return;
    if (appInForeground && activeChannel == channel) return;
    final c = store.channels[channel];
    if (c == null) return;
    final mentioned = (e['mentions'] as List?)?.contains(store.userId) ?? false;
    if (store.isMuted(channel)) return;
    final level = store.notifyLevel(channel);
    if (level == 'none' || (level == 'mention' && !mentioned)) return;
    final isServer = c['channel_type'] == 'TextChannel';
    final author = store.displayName(
      e['author'] as String?,
      server: c['server'] as String?,
    );
    final title = isServer ? '$author (#${c['name']})' : author;
    sounds?.play('message');
    _show(
      title,
      (e['content'] as String?) ?? 'Sent an attachment',
      payload: '/channel/$channel',
    );
  }

  Future<void> _show(String title, String body, {String? payload}) async {
    if (kIsWeb) {
      web_push.showLocal(title, body);
      return;
    }
    if (!_localReady) return;
    try {
      await _local.show(
        id: _nid++ & 0x7fffffff,
        title: title,
        body: body,
        payload: payload,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'messages',
            'Messages',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
          linux: LinuxNotificationDetails(),
          windows: WindowsNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('Showing notification failed: $e');
    }
  }

  @override
  void dispose() {
    _events?.cancel();
    _rustSub?.cancel();
    _tokenSub?.cancel();
    store.removeListener(_onStoreChanged);
    super.dispose();
  }
}
