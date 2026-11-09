import 'dart:async';
import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../net_image.dart';
import '../image_paste_region.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/client_store.dart';
import '../../api/permissions.dart';
import '../../core/css_colour.dart';
import '../../core/emoji_data.dart';
import '../../core/links.dart';
import '../../state/draft_store.dart';
import '../../state/settings_store.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../messaging/embeds.dart' show humanFileSize;
import '../messaging/markdown_view.dart';
import '../messaging/media_picker.dart';
import '../messaging/message_tile.dart';
import '../modals/app_dialog.dart';
import '../widgets.dart';
import '../../core/i18n.dart';

const _imageTypes = {'image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/avif', 'image/bmp'};

String mimeFromName(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'avif' => 'image/avif',
    'bmp' => 'image/bmp',
    'mp4' => 'video/mp4',
    'webm' => 'video/webm',
    'mov' => 'video/quicktime',
    'mp3' => 'audio/mpeg',
    'ogg' => 'audio/ogg',
    'wav' => 'audio/wav',
    'pdf' => 'application/pdf',
    'txt' => 'text/plain',
    _ => 'application/octet-stream',
  };
}

final _rnd = Random();
String _fileId() => '${DateTime.now().microsecondsSinceEpoch}${_rnd.nextInt(1 << 20)}';

/// Adds files to a channel draft after enforcing the instance upload limits.
void addDraftFiles(BuildContext context, String channelId, List<({String name, Uint8List bytes, String? mime})> files) {
  final store = context.read<ClientStore>();
  final drafts = context.read<DraftStore>();
  if (!store.can(channelId, Perm.sendMessage) || !store.can(channelId, Perm.uploadFiles)) return;
  final max = store.api.config?.fileLimit('attachments') ?? 20000000;
  final rejected = <({String name, int size})>[];
  for (final f in files) {
    if (f.bytes.length > max) {
      rejected.add((name: f.name, size: f.bytes.length));
    } else {
      drafts.addFile(channelId, DraftFile(id: _fileId(), name: f.name, mime: f.mime ?? mimeFromName(f.name), bytes: f.bytes));
    }
  }
  if (rejected.isNotEmpty) {
    final lim = humanFileSize(max);
    showAppDialog<void>(
      context,
      title: rejected.length == 1 ? 'File too large' : 'Files too large',
      content: Text(
        rejected.length == 1
            ? 'The file "${rejected.first.name}" (${humanFileSize(rejected.first.size)}) exceeds the maximum size limit of $lim.'
            : '${rejected.length} files exceed the maximum size limit of $lim and were not uploaded.',
      ),
    );
  }
}

Future<void> pickFilesInto(BuildContext context, String channelId) async {
  final res = await FilePicker.pickFiles(allowMultiple: true, withData: true);
  if (res == null || !context.mounted) return;
  addDraftFiles(context, channelId, [
    for (final f in res.files)
      if (f.bytes != null) (name: f.name, bytes: f.bytes!, mime: null),
  ]);
}

/// Text controller that styles Markdown while typing (CodeMirror marks of the web client).
class MarkdownEditingController extends TextEditingController {
  MarkdownEditingController({super.text});

  static final _rules = <(RegExp, TextStyle Function(TextStyle base, ColorScheme cs))>[
    (RegExp(r'^#{1,6} .*$', multiLine: true), (b, cs) => b.copyWith(fontWeight: FontWeight.w600)),
    (RegExp(r'\*\*[^*\n]+\*\*'), (b, cs) => b.copyWith(fontWeight: FontWeight.bold)),
    (RegExp(r'(?<![*\w])\*[^*\n]+\*(?![*\w])|(?<!\w)_[^_\n]+_(?!\w)'), (b, cs) => b.copyWith(fontStyle: FontStyle.italic)),
    (RegExp(r'~~[^~\n]+~~'), (b, cs) => b.copyWith(decoration: TextDecoration.lineThrough)),
    (RegExp(r'`[^`\n]+`'), (b, cs) => b.copyWith(fontFamily: 'monospace', backgroundColor: const Color(0xFF0D1117), color: const Color(0xFFC9D1D9))),
    (RegExp(r'^> .*$', multiLine: true), (b, cs) => b.copyWith(color: cs.onSecondaryContainer, backgroundColor: cs.secondaryContainer)),
    (RegExp(r'https?://[^\s<>]+'), (b, cs) => b.copyWith(decoration: TextDecoration.underline)),
  ];

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final base = style ?? const TextStyle();
    final cs = Theme.of(context).colorScheme;
    if (text.isEmpty || value.composing.isValid && withComposing && !value.composing.isCollapsed) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }
    final styles = List<TextStyle?>.filled(text.length, null);
    for (final (re, fn) in _rules) {
      for (final m in re.allMatches(text)) {
        final s = fn(base, cs);
        for (var i = m.start; i < m.end; i++) {
          styles[i] = s;
        }
      }
    }
    final spans = <TextSpan>[];
    var start = 0;
    for (var i = 1; i <= text.length; i++) {
      if (i == text.length || styles[i] != styles[start]) {
        spans.add(TextSpan(text: text.substring(start, i), style: styles[start] ?? base));
        start = i;
      }
    }
    return TextSpan(style: base, children: spans);
  }
}

// ----- autocomplete -----

class _Suggestion {
  _Suggestion({required this.label, required this.apply, this.detail, this.url, this.colour, this.unicode, this.icon});
  final String label, apply;
  final String? detail, url, unicode;
  final Color? colour;
  final IconData? icon;
}

final _tokenRe = RegExp(r'(?<![\p{L}\w])[:@%#][\p{L}\w\-+]*$', unicode: true);

/// Composition area of a channel (`MessageComposition`).
class MessageComposer extends StatefulWidget {
  const MessageComposer({super.key, required this.channel, required this.onSent});
  final Json channel;
  final VoidCallback onSent;
  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  late final ClientStore _store = context.read<ClientStore>();
  late final DraftStore _drafts = context.read<DraftStore>();
  late final _ctl = MarkdownEditingController(text: _drafts.textFor(id));
  final _focus = FocusNode();
  final _anchorKey = GlobalKey();
  Timer? _typingStop;
  DateTime _lastTyping = DateTime.fromMillisecondsSinceEpoch(0);
  bool sending = false;
  List<_Suggestion> suggestions = const [];
  int selected = 0;
  int tokenStart = -1;
  Timer? _tick;

  String get id => widget.channel['_id'] as String;
  String? get serverId => widget.channel['server'] as String?;

  @override
  void initState() {
    super.initState();
    _ctl.addListener(_onText);
    _drafts.addListener(_onDraft);
    _focus.onKeyEvent = _onKey;
    EmojiData.load();
  }

  void _onDraft() {
    final t = _drafts.takeInsert();
    if (t == null) return;
    final sel = _ctl.selection;
    final text = _ctl.text;
    final at = sel.isValid ? sel.start : text.length;
    final ins = '$t ';
    _ctl.value = TextEditingValue(text: text.replaceRange(at, sel.isValid ? sel.end : at, ins), selection: TextSelection.collapsed(offset: at + ins.length));
    _focus.requestFocus();
  }

  @override
  void didUpdateWidget(covariant MessageComposer old) {
    super.didUpdateWidget(old);
    if (old.channel['_id'] != id) {
      context.read<DraftStore>().setText(old.channel['_id'] as String, _ctl.text);
      _ctl.text = context.read<DraftStore>().textFor(id);
      suggestions = const [];
    }
  }

  @override
  void dispose() {
    _drafts.removeListener(_onDraft);
    _drafts.setText(id, _ctl.text);
    _stopTyping();
    _typingStop?.cancel();
    _tick?.cancel();
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _phone => screenClassOf(MediaQuery.sizeOf(context)) == ScreenClass.phone;

  bool _timedOut(ClientStore store) {
    final sid = serverId;
    if (sid == null) return false;
    final t = store.members[sid]?[store.userId]?['timeout'] as String?;
    final d = t == null ? null : DateTime.tryParse(t);
    return d != null && d.isAfter(DateTime.now());
  }

  Duration? _slowmodeRemaining(ClientStore store) {
    final until = store.slowmodeUntil[id];
    if (until == null) return null;
    final r = until.difference(DateTime.now());
    return r.isNegative ? null : r;
  }

  void _onText() {
    _typing();
    _updateSuggestions();
    setState(() {});
  }

  void _typing() {
    final store = context.read<ClientStore>();
    if (_ctl.text.trim().isEmpty) return;
    final now = DateTime.now();
    if (now.difference(_lastTyping) > const Duration(milliseconds: 2500)) {
      _lastTyping = now;
      store.beginTyping(id);
    }
    _typingStop?.cancel();
    _typingStop = Timer(const Duration(seconds: 1), _stopTyping);
  }

  void _stopTyping() {
    if (_lastTyping.millisecondsSinceEpoch != 0) {
      _lastTyping = DateTime.fromMillisecondsSinceEpoch(0);
      _store.endTyping(id);
    }
  }

  // ----- suggestions -----

  void _updateSuggestions() {
    final sel = _ctl.selection;
    if (!sel.isValid || !sel.isCollapsed) {
      suggestions = const [];
      return;
    }
    final before = _ctl.text.substring(0, sel.start);
    if (RegExp(r'```').allMatches(before).length.isOdd) {
      suggestions = const [];
      return;
    }
    final m = _tokenRe.firstMatch(before);
    if (m == null) {
      suggestions = const [];
      return;
    }
    final token = m.group(0)!;
    final q = token.substring(1).toLowerCase();
    tokenStart = m.start;
    final store = context.read<ClientStore>();
    final out = <_Suggestion>[];
    switch (token[0]) {
      case ':':
        if (q.isEmpty) break;
        for (final e in store.emojis.values) {
          final name = (e['name'] as String? ?? '');
          if (name.toLowerCase().contains(q)) {
            out.add(_Suggestion(label: ':$name:', apply: ':${e['_id']}: ', url: '$customEmojiBaseUrl/${e['_id']}'));
          }
        }
        final d = EmojiData.loaded;
        if (d != null) {
          for (final e in d.all) {
            for (final s in e.shorthands) {
              if (s.toLowerCase().contains(q)) {
                out.add(_Suggestion(label: ':$s:', apply: e.emoji, unicode: e.emoji));
                break;
              }
            }
          }
        }
      case '@':
        final ids = <String>[];
        final sid = serverId;
        if (sid != null) {
          ids.addAll(store.members[sid]?.keys ?? const []);
        } else if (widget.channel['recipients'] is List) {
          ids.addAll((widget.channel['recipients'] as List).cast<String>());
        } else {
          ids.addAll(store.users.keys);
        }
        if (sid != null) {
          for (final special in ['everyone', 'online']) {
            if (special.contains(q)) out.add(_Suggestion(label: '@$special', apply: '@$special ', icon: Icons.alternate_email));
          }
        }
        for (final uid in ids) {
          final name = store.displayName(uid, server: sid);
          final uname = store.user(uid)?['username'] as String? ?? '';
          if (name.toLowerCase().contains(q) || uname.toLowerCase().contains(q)) {
            out.add(_Suggestion(
              label: '@$name',
              apply: '<@$uid> ',
              detail: name != uname ? '$uname#${store.user(uid)?['discriminator'] ?? ''}' : null,
              url: store.avatarUrl(uid, size: 48),
            ));
          }
        }
      case '%':
        final roles = (store.servers[serverId]?['roles'] as Map?)?.cast<String, dynamic>() ?? const {};
        for (final e in roles.entries) {
          final name = (e.value['name'] as String? ?? '');
          if (name.toLowerCase().contains(q)) {
            out.add(_Suggestion(label: '%$name', apply: '<%${e.key}> ', colour: parseCssColour(e.value['colour'] as String?)));
          }
        }
      case '#':
        final chans = serverId != null ? store.channelsOfServer(serverId!) : store.channels.values.toList();
        for (final c in chans) {
          final name = c['name'] as String? ?? '';
          if (name.toLowerCase().contains(q)) out.add(_Suggestion(label: '#$name', apply: '<#${c['_id']}> ', icon: Icons.tag));
        }
    }
    out.sort((a, b) {
      final pa = a.label.toLowerCase().startsWith(token[0] + q) ? 0 : 1;
      final pb = b.label.toLowerCase().startsWith(token[0] + q) ? 0 : 1;
      return pa != pb ? pa - pb : a.label.length - b.label.length;
    });
    suggestions = out.take(12).toList();
    selected = 0;
  }

  void _accept(_Suggestion s) {
    final sel = _ctl.selection;
    final text = _ctl.text;
    final end = sel.start;
    final newText = text.replaceRange(tokenStart, end, s.apply);
    _ctl.value = TextEditingValue(text: newText, selection: TextSelection.collapsed(offset: tokenStart + s.apply.length));
    suggestions = const [];
    _focus.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (suggestions.isNotEmpty) {
      if (k == LogicalKeyboardKey.arrowDown) {
        setState(() => selected = (selected + 1) % suggestions.length);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowUp) {
        setState(() => selected = (selected - 1 + suggestions.length) % suggestions.length);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.tab || k == LogicalKeyboardKey.numpadEnter) {
        _accept(suggestions[selected]);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.escape) {
        setState(() => suggestions = const []);
        return KeyEventResult.handled;
      }
    }
    if ((k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) && !_phone) {
      final shift = HardwareKeyboard.instance.isShiftPressed;
      final inFence = RegExp(r'```').allMatches(_ctl.text.substring(0, max(0, _ctl.selection.start))).length.isOdd;
      if (shift || inFence) return KeyEventResult.ignored;
      _send();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp && _ctl.text.isEmpty) {
      _editLast();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      final drafts = context.read<DraftStore>();
      if (drafts.filesFor(id).isNotEmpty) {
        drafts.removeFile(id, drafts.filesFor(id).last.id);
        return KeyEventResult.handled;
      }
      final r = drafts.repliesFor(id);
      if (r.isNotEmpty) {
        drafts.removeReply(id, r.last.id);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _editLast() {
    final store = context.read<ClientStore>();
    final mine = (store.messages[id] ?? const []).reversed.where((m) => m['author'] == store.userId && m['system'] == null && m['pending'] != true).firstOrNull;
    if (mine != null) context.read<DraftStore>().setEditing(id, mine['_id'] as String);
  }

  // ----- sending -----

  bool _canSend(ClientStore store, DraftStore drafts) {
    final len = _ctl.text.characters.length;
    final max = store.api.config?.messageLength ?? 2000;
    return len <= max &&
        (_ctl.text.trim().isNotEmpty || drafts.filesFor(id).isNotEmpty) &&
        _slowmodeRemaining(store) == null &&
        !_timedOut(store) &&
        !sending;
  }

  Future<void> _send([String? override]) async {
    final store = context.read<ClientStore>();
    final drafts = context.read<DraftStore>();
    if (override == null && !_canSend(store, drafts)) return;
    if (_slowmodeRemaining(store) != null) return;
    _stopTyping();
    final content = override ?? _ctl.text.trim();
    final files = override == null ? List<DraftFile>.of(drafts.filesFor(id)) : <DraftFile>[];
    final replies = [
      for (final r in drafts.repliesFor(id)) {'id': r.id, 'mention': r.mention},
    ];
    widget.onSent();
    if (override == null) {
      _ctl.clear();
      drafts.setText(id, '');
    }
    drafts.clearFiles(id);
    drafts.clearReplies(id);
    setState(() => sending = files.isNotEmpty);
    try {
      final ids = <String>[];
      for (final f in files) {
        ids.add(await store.api.uploadFile('attachments', f.spoiler && !f.name.startsWith('SPOILER_') ? 'SPOILER_${f.name}' : f.name, f.mime, f.bytes));
      }
      await store.sendMessage(id, content, attachments: ids, replies: replies);
    } catch (e) {
      if (mounted) {
        if (e is ApiException && e.status == 429) {
          setState(() {});
        } else {
          showSnack(context, errorText(e));
        }
      }
    } finally {
      if (mounted) {
        setState(() => sending = false);
        _focus.requestFocus();
      }
    }
  }

  Rect _anchorRect() {
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return Rect.zero;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _openPicker(PickerTab tab) {
    showMediaPicker(
      context,
      anchor: _anchorRect(),
      tab: tab,
      serverId: serverId,
      onText: (text) {
        final sel = _ctl.selection;
        final t = _ctl.text;
        final at = sel.isValid ? sel.start : t.length;
        _ctl.value = TextEditingValue(text: t.replaceRange(at, sel.isValid ? sel.end : at, text), selection: TextSelection.collapsed(offset: at + text.length));
      },
      onMessage: (c) => _send(c),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final drafts = context.watch<DraftStore>();
    final settings = context.watch<SettingsStore>();
    final cs = context.cs;
    final type = widget.channel['channel_type'] as String;
    final canSendPerm = store.can(id, Perm.sendMessage);
    final canUpload = canSendPerm && store.can(id, Perm.uploadFiles);
    final timedOut = _timedOut(store);
    final sendingAllowed = canSendPerm && !timedOut;
    final len = _ctl.text.characters.length;
    final maxLen = store.api.config?.messageLength ?? 2000;
    final canSend = _canSend(store, drafts);
    final placeholder = type == 'SavedMessages'
        ? 'Save to your notes'
        : type == 'DirectMessage'
        ? 'Message ${store.channelName(widget.channel)}'
        : 'Message ${widget.channel['name']}';
    final slow = _slowmodeRemaining(store);
    if (slow != null && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (_slowmodeRemaining(store) == null) {
          _tick?.cancel();
          _tick = null;
        }
        setState(() {});
      });
    }

    final replies = drafts.repliesFor(id);
    final files = drafts.filesFor(id);
    final maxHeight = MediaQuery.sizeOf(context).height * Layout.messageBoxHeightFactor;

    Widget box = Container(
      key: _anchorKey,
      constraints: BoxConstraints(maxHeight: maxHeight),
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(Radius_.xl),
          right: Radius.circular(settings.showSendButton ? Radius_.md : Radius_.xl),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (timedOut || !canSendPerm)
            Padding(padding: const EdgeInsets.only(bottom: 8, right: 8), child: Icon(Icons.block, size: 24, color: cs.onSurface))
          else if (store.can(id, Perm.uploadFiles))
            SizedBox(width: 42, height: 42, child: IconButton(icon: const Icon(Icons.add), onPressed: () => pickFilesInto(context, id)))
          else
            const SizedBox(width: 14),
          Expanded(
            child: timedOut
                ? Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Text(tr("You are timed out and can't send messages right now."), style: TextStyle(fontSize: 14)))
                : !canSendPerm
                ? Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Text(tr("You don't have permission to send messages in this channel."), style: TextStyle(fontSize: 14)))
                : ImagePasteRegion(
                    key: ValueKey(id),
                    focusNode: _focus,
                    enabled: canUpload && !sending,
                    onImage: (bytes, mime, name) {
                      if (_timedOut(store)) return;
                      addDraftFiles(context, id, [
                        (name: name, bytes: bytes, mime: mime),
                      ]);
                    },
                    onError: (error) => showSnack(context, errorText(error)),
                    builder: (context, menuBuilder) => TextField(
                      contextMenuBuilder: menuBuilder,
                      controller: _ctl,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 12,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      style: TextStyle(fontSize: settings.messageSize, color: cs.onSurface),
                      decoration: InputDecoration(
                        hintText: placeholder,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
          ),
          if (sendingAllowed)
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (len > maxLen - 200)
                  Text(len > maxLen + 9999 ? 'Too Long' : '${maxLen - len}', style: TextStyle(fontSize: 12, color: len > maxLen ? cs.error : cs.onSurface)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!canSend) SizedBox(width: 42, height: 42, child: IconButton(tooltip: 'GIFs', icon: const Icon(Icons.gif_box_outlined), onPressed: () => _openPicker(PickerTab.gif))),
                    SizedBox(width: 42, height: 42, child: IconButton(tooltip: tr('Emoji'), icon: const Icon(Icons.mood), onPressed: () => _openPicker(PickerTab.emoji))),
                  ],
                ),
              ],
            ),
        ],
      ),
    );

    final sendButton = settings.showSendButton && sendingAllowed
        ? Padding(
            padding: const EdgeInsets.only(left: Gap.md),
            child: SizedBox(
              width: 48,
              height: 48,
              child: IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: canSend ? cs.primary : cs.secondaryContainer,
                  foregroundColor: canSend ? cs.onPrimary : cs.onSecondaryContainer,
                  shape: RoundedRectangleBorder(borderRadius: br(Radius_.md)),
                ),
                onPressed: canSend ? _send : null,
                icon: sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
              ),
            ),
          )
        : const SizedBox.shrink();

    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (suggestions.isNotEmpty) _SuggestionList(items: suggestions, selected: selected, onPick: _accept),
        if (files.isNotEmpty) FileCarousel(files: files, channelId: id, onAdd: () => pickFilesInto(context, id), limit: store.api.config?.messageAttachments ?? 5),
        for (final r in replies)
          _ReplyPreview(
            channelId: id,
            serverId: serverId,
            reply: r,
            self: store.messageById(id, r.id)?['author'] == store.userId,
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: Gap.md),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [Expanded(child: box), sendButton]),
        ),
      ],
    );

    final dropTarget = canUpload
        ? DropTarget(
            onDragDone: (d) async {
              final list = <({String name, Uint8List bytes, String? mime})>[];
              for (final f in d.files) {
                list.add((name: f.name, bytes: await f.readAsBytes(), mime: f.mimeType));
              }
              if (mounted) addDraftFiles(context, id, list);
            },
            child: column,
          )
        : column;
    return dropTarget;
  }
}

class _SuggestionList extends StatelessWidget {
  const _SuggestionList({required this.items, required this.selected, required this.onPick});
  final List<_Suggestion> items;
  final int selected;
  final void Function(_Suggestion) onPick;
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Container(
      margin: const EdgeInsets.only(bottom: Gap.md),
      constraints: const BoxConstraints(maxHeight: 240),
      decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: br(Radius_.md), boxShadow: [BoxShadow(color: cs.shadow, blurRadius: 3)]),
      clipBehavior: Clip.antiAlias,
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: items.length,
        itemBuilder: (c, i) {
          final s = items[i];
          Widget? lead;
          if (s.unicode != null) {
            lead = EmojiView(s.unicode!, size: 22);
          } else if (s.url != null) {
            lead = ClipRRect(borderRadius: br(s.label.startsWith(':') ? 2 : 11), child: NetImage(s.url!, width: 22, height: 22, errorBuilder: (_, _, _) => const SizedBox(width: 22, height: 22)));
          } else if (s.icon != null) {
            lead = Icon(s.icon, size: 18);
          }
          return Material(
            color: i == selected ? cs.onSurface.withValues(alpha: .08) : Colors.transparent,
            child: InkWell(
              onTap: () => onPick(s),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  spacing: 8,
                  children: [
                    if (lead != null) lead,
                    Text(s.label, style: TextStyle(color: s.colour ?? cs.onSurface, fontWeight: FontWeight.w500)),
                    if (s.detail != null) Text(s.detail!, style: TextStyle(fontSize: 12, color: cs.outline)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ReplyPreview extends StatelessWidget {
  const _ReplyPreview({required this.channelId, required this.serverId, required this.reply, required this.self});
  final String channelId;
  final String? serverId;
  final ({String id, bool mention}) reply;
  final bool self;
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final drafts = context.read<DraftStore>();
    return Container(
      margin: const EdgeInsets.only(bottom: Gap.md),
      padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
      decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: br(Radius_.lg)),
      child: DefaultTextStyle.merge(
        style: TextStyle(fontSize: 12.8, color: cs.onPrimaryContainer),
        child: Row(
          spacing: 8,
          children: [
            Text(tr('Replying to')),
            Expanded(child: MessageReply(channelId: channelId, messageId: reply.id, serverId: serverId, noDecorations: true)),
            if (!self)
              InkWell(
                onTap: () => drafts.toggleMention(channelId, reply.id),
                child: Row(
                  spacing: 4,
                  children: [
                    Icon(Icons.alternate_email, size: 16, color: reply.mention ? cs.onPrimaryContainer : cs.outline),
                    Text(reply.mention ? 'ON' : 'OFF', style: TextStyle(color: reply.mention ? cs.onPrimaryContainer : cs.outline)),
                  ],
                ),
              ),
            const SizedBox(width: 4),
            InkWell(onTap: () => drafts.removeReply(channelId, reply.id), child: const Icon(Icons.cancel, size: 16)),
          ],
        ),
      ),
    );
  }
}

/// Preview strip of attached files (`FileCarousel`).
class FileCarousel extends StatelessWidget {
  const FileCarousel({super.key, required this.files, required this.channelId, required this.onAdd, required this.limit});
  final List<DraftFile> files;
  final String channelId;
  final VoidCallback onAdd;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final drafts = context.read<DraftStore>();
    const size = 100.0;

    Widget actionIcon(IconData icon, VoidCallback onTap, {bool danger = false}) => InkWell(
      onTap: onTap,
      borderRadius: br(Radius_.sm),
      child: SizedBox(width: 22, height: 22, child: Icon(icon, size: 16, color: danger ? cs.error : cs.onSurface)),
    );

    Widget entry(int i, DraftFile f) {
      final isImage = _imageTypes.contains(f.mime);
      return Opacity(
        opacity: i >= limit ? .4 : 1,
        child: Column(
          children: [
            ClipRRect(
              borderRadius: br(Gap.md),
              child: Container(
                width: size,
                height: size,
                color: cs.surfaceContainerHighest,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (isImage)
                      ImageFiltered(
                        enabled: f.spoiler,
                        imageFilter: _blur,
                        child: Image.memory(f.bytes, fit: BoxFit.cover),
                      )
                    else
                      Center(child: Icon(Icons.description_outlined, size: 36, color: cs.onSurfaceVariant)),
                    if (f.spoiler)
                      Center(
                        child: InkWell(
                          onTap: () => drafts.toggleSpoiler(channelId, f.id),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 4),
                            decoration: BoxDecoration(color: cs.surface, borderRadius: br(Radius_.lg)),
                            child: Text('SPOILER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurface)),
                          ),
                        ),
                      ),
                    Positioned(
                      top: Gap.sm,
                      right: Gap.sm,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(color: cs.surface, borderRadius: br(Radius_.md)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          spacing: 2,
                          children: [
                            actionIcon(f.spoiler ? Icons.visibility_off : Icons.visibility, () => drafts.toggleSpoiler(channelId, f.id)),
                            actionIcon(Icons.delete, () => drafts.removeFile(channelId, f.id), danger: true),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(width: size, child: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
            Text(humanFileSize(f.bytes.length), style: TextStyle(fontSize: 11, color: cs.onPrimaryContainer.withValues(alpha: .8))),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: Gap.md, top: Gap.md),
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: br(Radius_.lg)),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: cs.onPrimaryContainer),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Gap.md,
            children: [
              for (var i = 0; i < files.length; i++) ...[
                if (i == limit) Container(height: 130, width: Gap.sm, decoration: BoxDecoration(color: cs.outline, borderRadius: br(Radius_.md))),
                entry(i, files[i]),
              ],
              InkWell(
                onTap: onAdd,
                borderRadius: br(Gap.md),
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: br(Gap.md)),
                  child: Icon(Icons.add, size: 48, color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final _blur = ImageFilter.blur(sigmaX: 28, sigmaY: 28);

/// Typing + slowmode strip between the message list and the composer (`CompositionInfo`).
class CompositionInfoBar extends StatefulWidget {
  const CompositionInfoBar({super.key, required this.channel});
  final Json channel;
  @override
  State<CompositionInfoBar> createState() => _CompositionInfoBarState();
}

class _CompositionInfoBarState extends State<CompositionInfoBar> {
  Timer? _t;

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  String _fmtDuration(int seconds) {
    final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60, s = seconds % 60;
    String p(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '$h:${p(m)}:${p(s)}' : '${p(m)}:${p(s)}';
  }

  String _human(int seconds) {
    final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60, s = seconds % 60;
    return [if (h > 0) '$h hour${h == 1 ? '' : 's'}', if (m > 0) '$m minute${m == 1 ? '' : 's'}', if (s > 0) '$s second${s == 1 ? '' : 's'}'].join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final cs = context.cs;
    final id = widget.channel['_id'] as String;
    final typers = (store.typing[id] ?? {}).where((u) => u != store.userId && store.user(u)?['relationship'] != 'Blocked').toList()..sort();
    final slowmode = (widget.channel['slowmode'] as num?)?.toInt() ?? 0;
    if (slowmode == 0 && typers.isEmpty) return const SizedBox.shrink();

    String? slowText;
    if (slowmode > 0) {
      if (store.can(id, Perm.bypassSlowmode)) {
        slowText = 'Slowmode Immune';
      } else {
        final until = store.slowmodeUntil[id];
        final left = until?.difference(DateTime.now()).inSeconds ?? 0;
        if (left > 0) {
          slowText = _fmtDuration(left);
          _t ??= Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted) setState(() {});
          });
        } else {
          slowText = 'Slowmode is enabled.';
        }
      }
    }

    final names = [for (final u in typers) store.user(u)?['username'] as String? ?? 'Unknown'];
    final typingText = typers.isEmpty
        ? null
        : typers.length == 1
        ? '${names.first} is typing…'
        : typers.length < 5
        ? '${names.sublist(0, names.length - 1).join(', ')} and ${names.last} are typing…'
        : 'Several people are typing…';

    return Container(
      constraints: const BoxConstraints(minHeight: 26),
      padding: const EdgeInsets.only(left: Gap.lg, right: Gap.md),
      color: cs.surfaceContainerLowest,
      child: Row(
        spacing: Gap.md,
        children: [
          if (typers.isNotEmpty)
            SizedBox(
              height: 15,
              width: 15.0 + (typers.length - 1) * 9,
              child: Stack(
                children: [
                  for (var i = 0; i < typers.length; i++) Positioned(left: i * 9.0, child: UserAvatar(userId: typers[i], size: 15)),
                ],
              ),
            ),
          if (typingText != null) Flexible(child: Text(typingText, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cs.onSurface))),
          const Spacer(),
          if (slowText != null)
            Tooltip(
              message: 'Members can send one message every ${_human(slowmode)}.',
              child: Row(
                spacing: 4,
                children: [
                  Icon(Icons.schedule, size: 16, color: cs.outline),
                  Text(slowText, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.outline)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
