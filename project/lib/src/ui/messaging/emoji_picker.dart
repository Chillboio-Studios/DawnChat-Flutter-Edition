import 'package:flutter/material.dart';

import 'media_picker.dart';

/// Opens the emoji picker near [context]'s widget and resolves with ":ID:" for custom emoji or a unicode string.
Future<String?> pickEmoji(BuildContext context, {String? serverId}) {
  final box = context.findRenderObject();
  Rect anchor;
  if (box is RenderBox && box.hasSize) {
    anchor = box.localToGlobal(Offset.zero) & box.size;
  } else {
    final s = MediaQuery.sizeOf(context);
    anchor = Rect.fromLTWH(s.width - 16, s.height - 80, 0, 0);
  }
  String? picked;
  return showMediaPicker(
    context,
    anchor: anchor,
    tab: PickerTab.emoji,
    serverId: serverId,
    onText: (t) {
      picked = t;
      Navigator.of(context, rootNavigator: true).pop();
    },
    onMessage: (_) {},
  ).then((_) => picked);
}
