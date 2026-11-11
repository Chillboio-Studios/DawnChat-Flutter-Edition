import 'package:flutter/foundation.dart';

import '../core/json.dart';

/// Per-channel composer state shared between the message list, toolbar and composer.
class DraftStore extends ChangeNotifier {
  final Map<String, List<({String id, bool mention})>> _replies = {};
  final Map<String, String> _editing = {};
  final Map<String, String> _text = {};

  List<({String id, bool mention})> repliesFor(String channel) =>
      _replies[channel] ?? const [];

  void addReply(Json message, String myId) {
    final ch = message['channel'] as String;
    final list = _replies[ch] ??= [];
    final id = message['_id'] as String;
    if (list.any((r) => r.id == id) || list.length >= 5) return;
    list.add((id: id, mention: message['author'] != myId));
    notifyListeners();
  }

  void removeReply(String channel, String id) {
    _replies[channel]?.removeWhere((r) => r.id == id);
    notifyListeners();
  }

  void toggleMention(String channel, String id) {
    final list = _replies[channel];
    if (list == null) return;
    final i = list.indexWhere((r) => r.id == id);
    if (i < 0) return;
    list[i] = (id: id, mention: !list[i].mention);
    notifyListeners();
  }

  void clearReplies(String channel) {
    _replies.remove(channel);
    notifyListeners();
  }

  String? editingIn(String channel) => _editing[channel];

  void setEditing(String channel, String? messageId) {
    if (messageId == null) {
      _editing.remove(channel);
    } else {
      _editing[channel] = messageId;
    }
    notifyListeners();
  }

  /// Set when the user presses Up on an empty composer; the list picks the latest own message.
  final Set<String> editLastRequested = {};
  void requestEditLast(String channel) {
    editLastRequested.add(channel);
    notifyListeners();
  }

  String textFor(String channel) => _text[channel] ?? '';
  void setText(String channel, String text) {
    if (text.isEmpty) {
      _text.remove(channel);
    } else {
      _text[channel] = text;
    }
  }

  /// Text another widget wants inserted at the composer cursor (e.g. "Mention" menu action).
  String? _pendingInsert;
  void requestInsert(String text) {
    _pendingInsert = text;
    notifyListeners();
  }

  String? takeInsert() {
    final t = _pendingInsert;
    _pendingInsert = null;
    return t;
  }

  final Map<String, List<DraftFile>> _files = {};
  List<DraftFile> filesFor(String channel) => _files[channel] ?? const [];

  void addFile(String channel, DraftFile f) {
    (_files[channel] ??= []).add(f);
    notifyListeners();
  }

  void removeFile(String channel, String id) {
    _files[channel]?.removeWhere((f) => f.id == id);
    notifyListeners();
  }

  void toggleSpoiler(String channel, String id) {
    final f = _files[channel]?.where((f) => f.id == id).firstOrNull;
    if (f == null) return;
    f.spoiler = !f.spoiler;
    notifyListeners();
  }

  void clearFiles(String channel) {
    _files.remove(channel);
    notifyListeners();
  }
}

class DraftFile {
  DraftFile({
    required this.id,
    required this.name,
    required this.mime,
    required this.bytes,
    this.spoiler = false,
  });
  final String id, name, mime;
  final Uint8List bytes;
  bool spoiler;
}
