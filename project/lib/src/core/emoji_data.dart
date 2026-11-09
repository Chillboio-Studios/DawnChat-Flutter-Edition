import 'dart:convert';

import 'package:flutter/services.dart';

class EmojiDef {
  const EmojiDef(this.emoji, this.shorthands);
  final String emoji;
  final List<String> shorthands;
}

/// Unicode emoji dataset shared with the web client (`emojiMapping.json`).
class EmojiData {
  EmojiData._(this.all, this.dedupe, this.byShorthand);
  final List<EmojiDef> all;
  final List<EmojiDef> dedupe;
  final Map<String, EmojiDef> byShorthand;

  static EmojiData? _instance;
  static Future<EmojiData>? _loading;

  static EmojiData? get loaded => _instance;

  static Future<EmojiData> load() => _loading ??= _doLoad();

  static Future<EmojiData> _doLoad() async {
    final raw = jsonDecode(await rootBundle.loadString('assets/data/emojiMapping.json')) as List;
    final all = <EmojiDef>[];
    final dedupe = <EmojiDef>[];
    final seen = <String>{};
    final map = <String, EmojiDef>{};
    for (final row in raw) {
      final list = (row as List).cast<String>();
      final def = EmojiDef(list.first, list.sublist(1));
      all.add(def);
      if (seen.add(def.emoji)) dedupe.add(def);
      for (final s in def.shorthands) {
        map[s] = def;
      }
    }
    return _instance = EmojiData._(all, dedupe, map);
  }
}
