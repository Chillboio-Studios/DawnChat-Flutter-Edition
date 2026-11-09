import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dawnchat/src/api/client_store.dart';
import 'package:dawnchat/src/app.dart';
import 'package:dawnchat/src/rust/frb_generated.dart';
import 'package:dawnchat/src/state/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _user = String.fromEnvironment('DC_USERNAME');
const _pass = String.fromEnvironment('DC_PASSWORD');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());

  testWidgets('logs in with the developer account and syncs', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsStore.load();
    final store = ClientStore(settings);
    await tester.runAsync(() async {
      await store.init();
      final mfa = await store.login(_user, _pass);
      expect(mfa, isNull);
      for (var i = 0; i < 100 && !store.ready; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    });
    expect(store.ready, isTrue);
    expect(store.me, isNotNull);

    await tester.runAsync(() async {
      final text = store.channels.values.where((c) => c['channel_type'] == 'TextChannel').firstOrNull ??
          store.channels.values.firstOrNull;
      if (text != null) {
        final got = await store.loadMessages(text['_id'] as String);
        // ignore: avoid_print
        print('LIVE loaded ${got.length} messages from ${text['channel_type']}');
        final sid = text['server'] as String?;
        if (sid != null) {
          await store.loadMembers(sid);
          // ignore: avoid_print
          print('LIVE members: ${store.members[sid]?.length}');
        }
      }
      final sessions = await store.sessions();
      // ignore: avoid_print
      print('LIVE sessions: ${sessions.length}, servers: ${store.servers.length}, channels: ${store.channels.length}, friends: ${store.friends.length}');
      final bots = await store.myBots();
      // ignore: avoid_print
      print('LIVE bots: ${bots.length}');
    });

    await tester.pumpWidget(DawnChatApp(settings: settings, store: store));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
