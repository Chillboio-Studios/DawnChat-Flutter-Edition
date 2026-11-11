import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dawnchat/src/api/client_store.dart';
import 'package:dawnchat/src/core/image_cache.dart';
import 'package:dawnchat/src/push/push_service.dart';
import 'package:dawnchat/src/router.dart';
import 'package:dawnchat/src/state/draft_store.dart';
import 'package:dawnchat/src/state/settings_store.dart';
import 'package:dawnchat/src/theme/app_theme.dart';
import 'package:dawnchat/src/ui/profile/profile.dart';
import 'package:dawnchat/src/ui/settings/settings_page.dart';
import 'package:dawnchat/src/voice/voice_manager.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _drain(WidgetTester t) {
  Object? ex;
  while ((ex = t.takeException()) != null) {
    final s = '$ex';
    if (!s.contains('google_fonts') && !s.contains('GoogleFonts')) {
      debugPrint('EXC: ${s.split('\n').take(6).join(' | ')}');
    }
  }
}

Future<void> _shot(
  WidgetTester tester,
  String location,
  Size size,
  String name, {
  AuthState auth = AuthState.loggedOut,
  void Function(ClientStore)? seed,
  Future<void> Function(WidgetTester)? onReady,
}) async {
  SharedPreferences.setMockInitialValues({});
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
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
  if (onReady != null) {
    await onReady(tester);
    await tester.pump(const Duration(milliseconds: 800));
  }
  // Google Fonts cannot download in tests; the exceptions are expected.
  Object? ex;
  while ((ex = tester.takeException()) != null) {
    final s = '$ex';
    if (!s.contains('google_fonts') && !s.contains('GoogleFonts')) {
      debugPrint('EXC: ${s.split('\n').take(5).join(' | ')}');
    }
  }
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
  debugDefaultTargetPlatformOverride = null;
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
    'profile modal desktop',
    (t) => _shot(
      t,
      '/server/01SERVER00000000000000000A/channel/C1',
      const Size(1280, 800),
      'profile_modal',
      auth: AuthState.loggedIn,
      seed: (s) {
        _seed(s);
        s.users['U2']!['status'] = {
          'text': 'Working on things',
          'presence': 'Online',
        };
        s.users['U2']!['badges'] = 16 | 1 | 4;
        s.users['U2']!['display_name'] = 'Mystic Pixie';
        s.servers['01SERVER00000000000000000A']!['roles'] = {
          'R1': {'name': 'Moderator', 'colour': '#ff7f50', 'rank': 1},
        };
        s.members['01SERVER00000000000000000A']!['U2']!['roles'] = ['R1'];
      },
      onReady: (t) async {
        showUserProfile(
          t.element(find.byType(Scaffold).first),
          'U2',
          serverId: '01SERVER00000000000000000A',
        );
        for (var i = 0; i < 4; i++) {
          await t.pump(const Duration(milliseconds: 300));
          _drain(t);
        }
      },
    ),
  );
  testWidgets(
    'profile editor desktop',
    (t) => _shot(
      t,
      '/app',
      const Size(1280, 800),
      'profile_editor',
      auth: AuthState.loggedIn,
      seed: _seed,
      onReady: (t) async {
        showSettings(t.element(find.byType(Scaffold).first), page: 'profile');
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 300));
          _drain(t);
        }
      },
    ),
  );

  testWidgets(
    'settings sessions desktop',
    (t) => _shot(
      t,
      '/app',
      const Size(1280, 800),
      'settings_desktop',
      auth: AuthState.loggedIn,
      seed: _seed,
      onReady: (t) async {
        showSettings(t.element(find.byType(Scaffold).first), page: 'language');
        await t.pump(const Duration(milliseconds: 600));
        _drain(t);
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 300));
        }
      },
    ),
  );
  testWidgets(
    'embeds desktop',
    (t) => _shot(
      t,
      '/server/01SERVER00000000000000000A/channel/C2',
      const Size(1280, 800),
      'embeds_desktop',
      auth: AuthState.loggedIn,
      seed: (s) {
        _seed(s);
        s.messages['C2'] = [
          {
            '_id': '01HZZZZZZZ0000000000000011',
            'channel': 'C2',
            'author': 'U2',
            'content': 'First line',
          },
          {
            '_id': '01HZZZZZZZ0000000000000012',
            'channel': 'C2',
            'author': 'U2',
            'content': 'Second line right after',
          },
          {
            '_id': '01HZZZZZZZ0000000000000013',
            'channel': 'C2',
            'author': 'U2',
            'content': 'Embed below',
            'embeds': [
              {
                'type': 'Website',
                'url': 'https://example.com',
                'site_name': 'Example',
                'title': 'An example website title that is quite long',
                'description': 'A description of the page that explains what it is about in a couple of sentences.',
                'colour': '#ff7f50',
              },
              {
                'type': 'Website',
                'url': 'https://youtu.be/x',
                'site_name': 'YouTube',
                'title': 'Video title',
                'special': {'type': 'YouTube', 'id': 'x'},
                'video': {
                  'url': 'https://example.com/v.mp4',
                  'width': 1280,
                  'height': 720,
                },
              },
            ],
          },
          {
            '_id': '01HZZZZZZZ0000000000000014',
            'channel': 'C2',
            'author': 'U1',
            'content': 'With a file',
            'attachments': [
              {
                '_id': 'F1',
                'tag': 'attachments',
                'filename': 'report.pdf',
                'size': 123456,
                'metadata': {'type': 'File'},
              },
            ],
          },
        ];
      },
    ),
  );

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
      onReady: (tester) async {
        final list = tester.widget<ScrollablePositionedList>(
          find.byType(ScrollablePositionedList),
        );
        expect(list.padding, const EdgeInsets.only(bottom: 12));
      },
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
