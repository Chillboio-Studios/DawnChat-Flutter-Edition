import 'package:dawnchat/src/api/api_client.dart';
import 'package:dawnchat/src/api/client_store.dart';
import 'package:dawnchat/src/state/settings_store.dart';
import 'package:dawnchat/src/ui/settings/permission_editor.dart';
import 'package:dawnchat/src/ui/settings/role_editor.dart';
import 'package:dawnchat/src/ui/settings/server_settings.dart';
import 'package:dawnchat/src/ui/settings/channel_settings.dart';
import 'package:dawnchat/src/ui/settings/settings_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api extends ApiClient {
  _Api() : super('https://example.invalid');
  final calls = <(String, String, Object?)>[];
  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    final user = <String, dynamic>{'_id': 'bot', 'username': 'Helper', 'display_name': 'Helper', 'bot': {'owner': 'owner'}};
    if (path == '/bots/bot') return {'bot': {'token': 'test-token', 'public': true}, 'user': user};
    if (path == '/users/bot/profile') return {'content': 'Existing bot bio'};
    if (path == '/users/bot') return user;
    throw StateError('Unexpected GET $path');
  }
  @override
  String defaultAvatar(String userId) => '';
  @override
  Future<dynamic> patch(String path, [Object? body]) async {
    calls.add(('PATCH', path, body));
    return <String, dynamic>{};
  }
  @override
  Future<dynamic> put(String path, [Object? body]) async {
    calls.add(('PUT', path, body));
    return <String, dynamic>{};
  }
}

void main() {
  test('tri-state changes preserve unrelated high bits and deny values', () {
    final initial = PermissionValue(BigInt.one << 39, BigInt.one << 35);
    final deny = initial.change(32, PermissionChoice.deny);
    expect(deny.allow, initial.allow);
    expect(deny.deny, (BigInt.one << 35) | (BigInt.one << 32));
    final allow = deny.change(32, PermissionChoice.allow);
    expect(allow.choice(32), PermissionChoice.allow);
    expect(allow.deny, initial.deny);
    final neutral = allow.change(32, PermissionChoice.neutral);
    expect(neutral.allow, initial.allow);
    expect(neutral.deny, initial.deny);
    expect(PermissionValue.from(deny.cached).payload, deny.payload);
  });

  testWidgets('server roles open a full editor and save tri-state permissions', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsStore.load();
    final api = _Api();
    final store = ClientStore(settings)..api = api..userId = 'owner';
    store.servers['server'] = {
      '_id': 'server', 'name': 'Test server', 'owner': 'owner',
      'roles': {'role': <String, dynamic>{'name': 'Moderator', 'hoist': true,
        'permissions': {'a': 1 << 39, 'd': 1 << 35}}},
    };
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider.value(value: store,
      child: const MaterialApp(home: ServerSettingsPage(serverId: 'server'))));
    await tester.tap(find.text('Roles'));
    await tester.pump();
    await tester.tap(find.text('Moderator'));
    await tester.pump();
    expect(find.byType(RoleEditor), findsOneWidget);
    expect(find.text('Hoist Role'), findsOneWidget);
    final editor = tester.widget<PermissionEditor>(find.byType(PermissionEditor));
    editor.onChanged(editor.value.change(32, PermissionChoice.deny));
    await tester.pump();
    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(api.calls, isNotEmpty);
    final request = api.calls.where((call) => call.$1 == 'PUT').single;
    expect(request.$2, '/servers/server/permissions/role');
    expect(request.$3, {'permissions': {'allow': 1 << 39, 'deny': (1 << 35) | (1 << 32)}});
    expect((store.servers['server']!['roles'] as Map)['role']['permissions'],
        {'a': 1 << 39, 'd': (1 << 35) | (1 << 32)});
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
  });

  testWidgets('channel role overrides preserve deny and high permission bits', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsStore.load();
    final api = _Api();
    final store = ClientStore(settings)..api = api..userId = 'owner';
    store.servers['server'] = {'roles': {'role': {'name': 'Moderator'}}};
    store.channels['channel'] = {
      '_id': 'channel', 'channel_type': 'TextChannel', 'name': 'general', 'server': 'server',
      'role_permissions': {'role': {'a': 1 << 39, 'd': 1 << 35}},
    };
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider.value(value: store,
      child: const MaterialApp(home: ChannelSettingsPage(channelId: 'channel'))));
    await tester.tap(find.text('Permissions'));
    await tester.pump();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Moderator').last);
    await tester.pumpAndSettle();
    final editor = tester.widget<PermissionEditor>(find.byType(PermissionEditor));
    editor.onChanged(editor.value.change(32, PermissionChoice.deny));
    await tester.pump();
    final save = find.widgetWithText(FilledButton, 'Save permissions');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    final request = api.calls.where((call) => call.$1 == 'PUT').single;
    expect(request.$2, '/channels/channel/permissions/role');
    expect(request.$3, {'permissions': {'allow': 1 << 39, 'deny': (1 << 35) | (1 << 32)}});
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
  });

  testWidgets('bot settings edit the bot profile rather than the owner', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsStore.load();
    final api = _Api();
    final store = ClientStore(settings)..api = api..userId = 'owner';
    store.users['owner'] = {'_id': 'owner', 'username': 'Owner'};
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: store),
        ChangeNotifierProvider.value(value: settings),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: BotView(id: 'bot', onBack: () {})),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Existing bot bio'), findsOneWidget);
    expect(find.text('Reset Token'), findsOneWidget);
    expect(find.text('Invite Bot'), findsOneWidget);
    final name = find.byWidgetPredicate((widget) => widget is TextField && widget.decoration?.labelText == 'Display Name');
    await tester.enterText(name, 'Updated Helper');
    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    final request = api.calls.where((call) => call.$1 == 'PATCH').single;
    expect(request.$2, '/users/bot');
    expect(request.$3, {'display_name': 'Updated Helper'});
    expect(store.users['owner']!['username'], 'Owner');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
  });
}