import 'package:dawnchat/src/desktop/desktop_io.dart';
import 'package:dawnchat/src/state/settings_store.dart';
import 'package:dawnchat/src/ui/image_paste_region.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('bottom message bar focuses without hiding or minimizing', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsStore.load();
    settings.customFrame = true;
    final focus = FocusNode();
    final calls = <String>[];
    var clipboardReads = 0;
    const windowChannel = MethodChannel('window_manager');
    const clipboardChannel = MethodChannel('pasteboard');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(windowChannel, (call) async {
      calls.add(call.method);
      return null;
    });
    messenger.setMockMethodCallHandler(clipboardChannel, (call) async {
      clipboardReads++;
      return null;
    });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      focus.dispose();
      settings.dispose();
      messenger.setMockMethodCallHandler(windowChannel, null);
      messenger.setMockMethodCallHandler(clipboardChannel, null);
    });

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
          home: Scaffold(
            body: Titlebar(
              child: Column(
                children: [
                  const Expanded(child: SizedBox()),
                  ImagePasteRegion(
                    focusNode: focus,
                    enabled: true,
                    onImage: (_, _, _) =>
                        fail('A click must not paste an image'),
                    onError: (error) => fail('$error'),
                    builder: (context, menuBuilder) => TextField(
                      key: const ValueKey('message-box'),
                      focusNode: focus,
                      contextMenuBuilder: menuBuilder,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final box = tester.getRect(find.byKey(const ValueKey('message-box')));
    for (final fraction in [0.1, 0.5, 0.9]) {
      await tester.tapAt(
        Offset(box.left + box.width * fraction, box.center.dy),
      );
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      expect(calls, isEmpty);
      expect(clipboardReads, 0);
    }

    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();
    expect(calls, ['minimize']);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
