import 'dart:async';

import 'package:dawnchat/src/ui/image_paste_region.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const pasteboard = MethodChannel('pasteboard');
  final png = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
  late TextEditingController controller;
  late FocusNode focus;
  late List<({Uint8List bytes, String mime, String name})> images;
  late List<Object> errors;
  Object? clipboardImage;
  String clipboardText = '';

  setUp(() {
    controller = TextEditingController();
    focus = FocusNode();
    images = [];
    errors = [];
    clipboardImage = null;
    clipboardText = '';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pasteboard, (call) async {
          if (call.method == 'image') {
            if (clipboardImage is Exception) throw clipboardImage!;
            if (clipboardImage is Future) {
              return await (clipboardImage as Future<Object?>);
            }
            return clipboardImage;
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') {
            return {'text': clipboardText};
          }
          if (call.method == 'Clipboard.hasStrings') {
            return {'value': clipboardText.isNotEmpty};
          }
          return null;
        });
  });

  tearDown(() {
    controller.dispose();
    focus.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pasteboard, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> mount(
    WidgetTester tester, {
    bool enabled = true,
    String channel = 'channel',
  }) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImagePasteRegion(
            key: ValueKey(channel),
            focusNode: focus,
            enabled: enabled,
            onImage: (bytes, mime, name) =>
                images.add((bytes: bytes, mime: mime, name: name)),
            onError: errors.add,
            builder: (context, menuBuilder) => TextField(
              controller: controller,
              focusNode: focus,
              contextMenuBuilder: menuBuilder,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
  }

  Future<void> paste(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  testWidgets('pastes an image attachment without replacing existing text', (
    tester,
  ) async {
    clipboardImage = png;
    await mount(tester);
    controller.text = 'caption';
    await paste(tester);
    expect(images.single.bytes, png);
    expect(images.single.mime, 'image/png');
    expect(images.single.name, 'clipboard.png');
    expect(controller.text, 'caption');
    expect(errors, isEmpty);
  });

  testWidgets('normal text paste replaces the current selection', (
    tester,
  ) async {
    clipboardText = 'world';
    await mount(tester);
    controller.value = const TextEditingValue(
      text: 'hello there',
      selection: TextSelection(baseOffset: 6, extentOffset: 11),
    );
    await paste(tester);
    expect(controller.text, 'hello world');
    expect(images, isEmpty);
  });

  testWidgets('disabled image paste retains text paste', (tester) async {
    clipboardImage = png;
    clipboardText = 'text';
    await mount(tester, enabled: false);
    await paste(tester);
    expect(controller.text, 'text');
    expect(images, isEmpty);
  });

  testWidgets('clipboard read errors are reported', (tester) async {
    clipboardImage = PlatformException(code: 'clipboard-denied');
    await mount(tester);
    await paste(tester);
    expect(images, isEmpty);
    expect(errors.single, isA<PlatformException>());
  });

  testWidgets('pending clipboard read is ignored after disposal', (
    tester,
  ) async {
    final pending = Completer<Object?>();
    clipboardImage = pending.future;
    await mount(tester);
    await paste(tester);
    await tester.pumpWidget(const SizedBox());
    pending.complete(png);
    await tester.pump();
    expect(images, isEmpty);
    expect(errors, isEmpty);
  });

  testWidgets('pending clipboard read is ignored after switching channel', (
    tester,
  ) async {
    final pending = Completer<Object?>();
    clipboardImage = pending.future;
    await mount(tester);
    await paste(tester);
    await mount(tester, channel: 'another-channel');
    pending.complete(png);
    await tester.pump();
    expect(images, isEmpty);
    expect(errors, isEmpty);
  });

  testWidgets('pending image is ignored if uploads become disabled', (
    tester,
  ) async {
    final pending = Completer<Object?>();
    clipboardImage = pending.future;
    await mount(tester);
    await paste(tester);
    await mount(tester, enabled: false);
    pending.complete(png);
    await tester.pump();
    expect(images, isEmpty);
  });

  testWidgets('unsupported clipboard image data is reported', (tester) async {
    clipboardImage = Uint8List.fromList([1, 2, 3]);
    await mount(tester);
    await paste(tester);
    expect(images, isEmpty);
    expect(errors.single, isA<FormatException>());
  });

  testWidgets('selection toolbar can paste an image without clipboard text', (
    tester,
  ) async {
    clipboardImage = png;
    await mount(tester);
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    editable.showToolbar();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste'));
    await tester.pump();
    expect(images.single.bytes, png);
    expect(errors, isEmpty);
  });
}
