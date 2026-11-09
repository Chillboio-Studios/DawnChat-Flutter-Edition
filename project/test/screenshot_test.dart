import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:DawnChat/src/api/client_store.dart';
import 'package:DawnChat/src/core/image_cache.dart';
import 'package:DawnChat/src/push/push_service.dart';
import 'package:DawnChat/src/router.dart';
import 'package:DawnChat/src/state/draft_store.dart';
import 'package:DawnChat/src/state/settings_store.dart';
import 'package:DawnChat/src/theme/app_theme.dart';
import 'package:DawnChat/src/voice/voice_manager.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _shot(
  WidgetTester tester,
  String location,
  Size size,
  String name, {
  AuthState auth = AuthState.loggedOut,
  void Function(ClientStore)? seed,
}) async {
  SharedPreferences.setMockInitialValues({});
  useDiskImageCache = false;
  GoogleFonts.config.allowRuntimeFetching = false;
  final settings = await SettingsStore.load();
  final store = ClientStore(settings)..authState = auth;
  seed?.call(store);
  final sounds = SoundService(settings);
  final voice = VoiceManager(store, settings, sounds);
  final push = PushService(store, settings);
  final router = buildRouter(store, settings);
  router.go(location);

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: store),
        Provider.value(value: sounds),
        ChangeNotifierProvider.value(value: voice),
        ChangeNotifierProvider.value(value: push),
        ChangeNotifierProvider(create: (_) => DraftStore()),
      ],
      child: RepaintBoundary(
        key: const ValueKey('root'),
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(settings, Brightness.dark),
          routerConfig: router,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 600));
  // Google Fonts cannot download in tests; the exceptions are expected.
  while (tester.takeException() != null) {}
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('root')),
    );
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ImageByteFormat.png);
    Directory('/tmp/shots').createSync(recursive: true);
    File('/tmp/shots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
  // Network images fail with HTTP 400 under the test binding.
  await tester.pump(const Duration(milliseconds: 200));
  while (tester.takeException() != null) {}
}

void _seed(ClientStore s) {
  s.userId = 'U1';
  s.ready = true;
  s.connection = LinkState.connected;
  s.users['U1'] = {
    '_id': 'U1',
    'username': 'Dawn',
    'discriminator': '0001',
    'online': true,
    'status': {'presence': 'Online'},
  };
  s.users['U2'] = {
    '_id': 'U2',
    'username': 'Mystic',
    'discriminator': '0002',
    'online': true,
    'relationship': 'Friend',
  };
  s.users['U3'] = {
    '_id': 'U3',
    'username': 'Fox',
    'discriminator': '0003',
    'online': false,
    'relationship': 'Incoming',
  };
  s.servers['01SERVER00000000000000000A'] = {
    '_id': '01SERVER00000000000000000A',
    'name': 'DawnChat Lounge',
    'owner': 'U1',
    'channels': ['C1', 'C2', 'C3'],
    'categories': [
      {
        'id': 'cat',
        'title': 'Community',
        'channels': ['C2', 'C3'],
      },
    ],
  };
  s.channels['C1'] = {
    '_id': 'C1',
    'channel_type': 'TextChannel',
    'server': '01SERVER00000000000000000A',
    'name': 'welcome',
    'description': 'Say hello',
  };
  s.channels['C2'] = {
    '_id': 'C2',
    'channel_type': 'TextChannel',
    'server': '01SERVER00000000000000000A',
    'name': 'general',
  };
  s.channels['C3'] = {
    '_id': 'C3',
    'channel_type': 'VoiceChannel',
    'server': '01SERVER00000000000000000A',
    'name': 'Hangout',
  };
  s.channels['D1'] = {
    '_id': 'D1',
    'channel_type': 'DirectMessage',
    'recipients': ['U1', 'U2'],
    'active': true,
  };
  s.members['01SERVER00000000000000000A'] = {
    'U1': {
      '_id': {'server': '01SERVER00000000000000000A', 'user': 'U1'},
    },
    'U2': {
      '_id': {'server': '01SERVER00000000000000000A', 'user': 'U2'},
    },
  };
  s.messages['C1'] = [
    {
      '_id': '01HZZZZZZZ0000000000000001',
      'channel': 'C1',
      'author': 'U2',
      'content': 'Welcome to **DawnChat**! Check https://dawn-chat.com',
    },
    {
      '_id': '01HZZZZZZZ0000000000000002',
      'channel': 'C1',
      'author': 'U2',
      'content': 'Second message in the same group',
    },
    {
      '_id': '01HZZZZZZZ0000000000000003',
      'channel': 'C1',
      'author': 'U1',
      'content': 'Hello `world`',
    },
  ];
}

void main() {
  testWidgets(
    'login desktop',
    (t) => _shot(t, '/login/auth', const Size(1280, 800), 'login_desktop'),
  );
  testWidgets(
    'login phone',
    (t) => _shot(t, '/login/auth', const Size(390, 844), 'login_phone'),
  );
  testWidgets(
    'create desktop',
    (t) => _shot(t, '/login/create', const Size(1280, 800), 'create_desktop'),
  );
  testWidgets(
    'home desktop',
    (t) => _shot(
      t,
      '/app',
      const Size(1280, 800),
      'home_desktop',
      auth: AuthState.loggedIn,
      seed: _seed,
    ),
  );
  testWidgets(
    'channel desktop',
    (t) => _shot(
      t,
      '/server/01SERVER00000000000000000A/channel/C1',
      const Size(1280, 800),
      'channel_desktop',
      auth: AuthState.loggedIn,
      seed: _seed,
    ),
  );
  testWidgets(
    'channel phone',
    (t) => _shot(
      t,
      '/server/01SERVER00000000000000000A/channel/C1',
      const Size(390, 844),
      'channel_phone',
      auth: AuthState.loggedIn,
      seed: _seed,
    ),
  );
  testWidgets(
    'home phone',
    (t) => _shot(
      t,
      '/app',
      const Size(390, 844),
      'home_phone',
      auth: AuthState.loggedIn,
      seed: _seed,
    ),
  );
}
