import 'package:dawnchat/src/api/client_store.dart';
import 'package:dawnchat/src/state/settings_store.dart';
import 'package:dawnchat/src/ui/channel/channel_sidebars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemberStore extends ClientStore {
  _MemberStore(super.settings);

  final requests = <String>[];
  bool fail = false;

  @override
  Future<void> loadMembers(String serverId) async {
    requests.add(serverId);
    await Future<void>.value();
    if (fail) throw StateError('Unavailable');
    users.addAll({
      'admin': {'_id': 'admin', 'username': 'Alice', 'online': true},
      'member': {'_id': 'member', 'username': 'Bob', 'online': true},
      'offline': {'_id': 'offline', 'username': 'Charlie', 'online': false},
    });
    members[serverId] = {
      'admin': {'roles': ['lower', 'higher']},
      'member': {'roles': <String>[]},
      'offline': {'roles': ['higher']},
    };
    notifyListeners();
  }

  @override
  String? avatarUrl(String? id, {double size = 64}) => null;
}

void main() {
  late _MemberStore store;
  late SettingsStore settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await SettingsStore.load();
    store = _MemberStore(settings);
    for (final serverId in ['server', 'other']) {
      store.servers[serverId] = {
        '_id': serverId,
        'roles': {
          'lower': {'name': 'Lower', 'hoist': true, 'rank': 10},
          'higher': {'name': 'Higher', 'hoist': true, 'rank': 1},
        },
      };
    }
    store.members['server'] = {'member': {'roles': <String>[]}};
    store.users['member'] = {'_id': 'member', 'username': 'Bob', 'online': true};
  });

  tearDown(() {
    settings.dispose();
  });

  Future<void> mount(WidgetTester tester, String serverId) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ClientStore>.value(value: store),
          ChangeNotifierProvider.value(value: settings),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: MemberSidebar(channel: {
              '_id': 'channel',
              'channel_type': 'TextChannel',
              'server': serverId,
            }),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('loads all members despite a partial cache and groups by role', (tester) async {
    await mount(tester, 'server');

    expect(store.requests, ['server']);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Charlie'), findsOneWidget);
    expect(find.text('Higher'), findsOneWidget);
    expect(find.text('Lower'), findsNothing);
    expect(find.text('2 members online'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Alice')).dy,
        lessThan(tester.getTopLeft(find.text('Bob')).dy));
    expect(tester.getTopLeft(find.text('Bob')).dy,
        lessThan(tester.getTopLeft(find.text('Charlie')).dy));

    await mount(tester, 'server');
    expect(store.requests, ['server']);
    await mount(tester, 'other');
    expect(store.requests, ['server', 'other']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed member requests can be retried', (tester) async {
    store.fail = true;
    await mount(tester, 'server');
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    store.fail = false;
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    await tester.pump();
    expect(store.requests, ['server', 'server']);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsNothing);
    expect(tester.takeException(), isNull);
  });
}