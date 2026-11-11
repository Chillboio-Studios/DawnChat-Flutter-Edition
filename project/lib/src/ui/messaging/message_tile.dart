import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../net_image.dart';

import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../api/client_store.dart';
import '../../api/permissions.dart';
import '../../core/css_colour.dart';
import '../../router.dart';
import '../../state/draft_store.dart';
import '../../state/settings_store.dart';
import '../../theme/tokens.dart';
import '../menus/context_menu.dart';
import '../menus/message_menu.dart';
import '../menus/user_menu.dart';
import '../modals/message_modals.dart';
import '../widgets.dart';
import 'embeds.dart';
import 'markdown_view.dart';
import 'time_utils.dart';
import '../../core/i18n.dart';

/// `isLink` of the web client: false, true, or "hide".
enum MessageLink { none, link, hide }

const _bridgeBotId = '01FHGJ3NPP7XANQQH8C2BE44ZY';
final _urlRe = RegExp(
  r'[(http(s)?)://(www.)?a-zA-Z0-9@:%._+~#=]{2,256}\.[a-z]{2,6}\b([-a-zA-Z0-9@:%_+.~#?&//=]*)',
);

bool _isMobile(BuildContext context) =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS ||
    MediaQuery.sizeOf(context).width <= 600;

/// One message in a channel (`Message` + `MessageContainer` of the web client).
class MessageTile extends StatefulWidget {
  const MessageTile({
    super.key,
    required this.message,
    this.serverId,
    this.tail = false,
    this.highlight = false,
    this.isLink = MessageLink.none,
    this.onTapLink,
  });
  final Json message;
  final String? serverId;
  final bool tail, highlight;
  final MessageLink isLink;
  final VoidCallback? onTapLink;

  @override
  State<MessageTile> createState() => _MessageTileState();
}

class _MessageTileState extends State<MessageTile> {
  bool hover = false;

  Json get m => widget.message;
  String get channelId => m['channel'] as String;

  bool _mentioned(ClientStore store) {
    final me = store.userId;
    if ((m['mentions'] as List?)?.contains(me) ?? false) return true;
    final sid = widget.serverId;
    final roles = (m['role_mentions'] as List?)?.cast<String>();
    if (sid != null && roles != null) {
      final mine =
          (store.members[sid]?[me]?['roles'] as List?)?.cast<String>() ??
          const [];
      if (roles.any(mine.contains)) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final settings = context.watch<SettingsStore>();
    final drafts = context.watch<DraftStore>();
    final cs = context.cs;
    final system = m['system'] as Map?;
    final compactMode = settings.compactMode;
    final compact = system != null || compactMode;
    final tail = widget.tail || compactMode;
    final author = m['author'] as String?;
    final sid = widget.serverId;
    final member = sid == null ? null : store.members[sid]?[author];
    final masq = m['masquerade'] as Map?;
    final webhook = m['webhook'] as Map?;
    final editing = drafts.editingIn(channelId) == m['_id'];
    final pending = m['pending'] == true;
    final failed = m['failed'] == true;
    final isLink = widget.isLink == MessageLink.link;
    final showToolbar =
        !_isMobile(context) &&
        widget.isLink == MessageLink.none &&
        !pending &&
        !failed;
    final user = store.user(author);

    final name =
        masq?['name'] as String? ??
        (webhook?['name'] as String?) ??
        member?['nickname'] as String? ??
        user?['display_name'] as String? ??
        user?['username'] as String? ??
        'Unknown User';
    final colour =
        parseCssColour(masq?['colour'] as String?) ??
        store.roleColour(author, sid);

    final avatarUrl = masq?['avatar'] != null
        ? '${store.api.config?.januaryUrl}/proxy?url=${Uri.encodeQueryComponent(masq!['avatar'] as String)}'
        : webhook?['avatar'] != null
        ? '${store.api.config?.autumnUrl}/avatars/${webhook!['avatar']}'
        : member?['avatar'] != null
        ? store.api.fileUrl('avatars', member!['avatar'] as Map, width: 72)
        : store.avatarUrl(author, size: 72);

    final base = TextStyle(
      fontSize: settings.messageSize,
      height: 1.4,
      color: failed
          ? cs.error
          : pending
          ? cs.outline
          : cs.onSurface,
    );

    void openCard() => openUserCard(context, author ?? '', serverId: sid);
    List<MenuItem> userItems() =>
        userMenu(context, author ?? '', serverId: sid, contextMessage: m);

    Widget usernameWidget() => MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: author == null || isLink ? null : openCard,
        onSecondaryTapUp: author == null
            ? null
            : (d) => showContextMenu(context, d.globalPosition, userItems()),
        child: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: colour ?? cs.onSurface,
            fontSize: settings.messageSize,
          ),
        ),
      ),
    );

    final avatar = GestureDetector(
      onTap: author == null || isLink ? null : openCard,
      onSecondaryTapUp: author == null
          ? null
          : (d) => showContextMenu(context, d.globalPosition, userItems()),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: UserAvatar(
          userId: author,
          size: 36,
          url: avatarUrl,
          fallbackName: name,
        ),
      ),
    );

    final sentAt = _safeUlid(m['_id'] as String);
    final editedAt = m['edited'] != null
        ? DateTime.tryParse(m['edited'] as String)?.toLocal()
        : null;
    final infoStyle = TextStyle(color: cs.outline, fontSize: 12, height: 1.4);

    // Info icons next to the username.
    final iconRole = store.iconRole(author, sid);
    Widget? info;
    if (iconRole != null) {
      info = Tooltip(
        message: iconRole['name'] as String? ?? '',
        child: ClipRRect(
          borderRadius: br(4),
          child: NetImage(
            store.api.fileUrl('icons', iconRole['icon'] as Map?, width: 32) ??
                '',
            width: 16,
            height: 16,
            errorBuilder: (_, _, _) => const SizedBox(width: 16, height: 16),
          ),
        ),
      );
    } else if (masq != null && author == _bridgeBotId) {
      info = _infoIcon(
        Icons.link,
        'Message was sent on another platform',
        cs.outline,
      );
    } else if (user?['privileged'] == true) {
      info = _infoIcon(
        Icons.campaign_outlined,
        'Official Communication',
        cs.outline,
      );
    } else if (user?['bot'] != null) {
      info = _infoIcon(Icons.smart_toy, 'Bot', cs.outline);
    } else if (webhook != null) {
      info = _infoIcon(Icons.cloud, 'Webhook', cs.outline);
    } else if (((m['flags'] as num?)?.toInt() ?? 0) & 1 != 0) {
      info = _infoIcon(Icons.notifications_off, 'Silent', cs.outline);
    } else if (_timedOut(member) &&
        sid != null &&
        store.can(channelId, Perm.timeoutMembers)) {
      info = _infoIcon(
        Icons.timer_off,
        'Timed Out until ${DateTime.parse(member!['timeout'] as String).toLocal()}',
        cs.error,
      );
    } else if (author != null && _ageDays(_safeUlid(author)) < 1) {
      info = _infoIcon(Icons.spa, 'New to DawnChat', cs.primary);
    } else if (member?['joined_at'] != null &&
        _ageDays(
              DateTime.tryParse(member!['joined_at'] as String) ??
                  DateTime(2000),
            ) <
            1) {
      info = _infoIcon(Icons.spa_outlined, 'New to the server', cs.primary);
    }

    final pronouns = _pronouns(member, user);

    // Left column.
    Widget leftColumn;
    if (system != null) {
      leftColumn = SystemMessageIcon(
        type: system['type'] as String,
        sentAt: sentAt,
        isServer: sid != null,
      );
    } else if (compact) {
      leftColumn = Padding(
        padding: const EdgeInsets.only(top: 0, left: 15, right: 0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [
            Tooltip(
              richMessage: TextSpan(
                text:
                    'Sent ${formatDateTime(settings, sentAt)}${editedAt != null ? '\nEdited ${formatDateTime(settings, editedAt)}' : ''}',
              ),
              child: Text(formatTime(settings, sentAt), style: infoStyle),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: usernameWidget(),
            ),
            ?info,
            if (editedAt != null) Icon(Icons.edit, size: 16, color: cs.outline),
          ],
        ),
      );
    } else if (tail) {
      leftColumn = SizedBox(
        width: 54,
        child: Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 4, top: 3),
            child: Opacity(
              opacity: editedAt != null || hover ? 1 : 0,
              child: Tooltip(
                richMessage: TextSpan(
                  text:
                      'Sent ${formatDateTime(settings, sentAt)}${editedAt != null ? '\nEdited ${formatDateTime(settings, editedAt)}' : ''}',
                ),
                child: Text(
                  editedAt != null ? '(edited)' : formatTime(settings, sentAt),
                  style: infoStyle.copyWith(fontSize: 10.5),
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      leftColumn = SizedBox(
        width: 54,
        child: Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
            child: avatar,
          ),
        ),
      );
    }

    final replies = (m['replies'] as List?)?.cast<String>() ?? const <String>[];
    final header = replies.isEmpty
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final r in replies)
                MessageReply(
                  channelId: channelId,
                  messageId: r,
                  serverId: sid,
                  mention:
                      (m['mentions'] as List?)?.contains(
                        store.messageById(channelId, r)?['author'],
                      ) ??
                      false,
                ),
            ],
          );

    final content = m['content'] as String?;
    final embeds = (m['embeds'] as List?)?.cast<Map>() ?? const <Map>[];
    final onlyGif =
        embeds.length == 1 &&
        isGif(embeds.first) &&
        content != null &&
        content.replaceFirst(_urlRe, '').isEmpty;
    final attachments =
        (m['attachments'] as List?)?.cast<Map>() ?? const <Map>[];

    final bodyChildren = <Widget>[
      if (system != null)
        SystemMessageView(
          system: system,
          isServer: sid != null,
          channelId: channelId,
          serverId: sid,
          sentAt: sentAt,
        ),
      if (editing)
        InlineEditor(message: m)
      else if (content != null &&
          content.isNotEmpty &&
          !onlyGif &&
          system == null)
        RichContent(content, serverId: sid),
      for (final a in attachments)
        Align(
          alignment: Alignment.centerLeft,
          child: AttachmentView(
            file: a,
            onSecondaryTap: widget.isLink == MessageLink.none
                ? (p) => showContextMenu(
                    context,
                    p,
                    messageMenu(context, m, file: a),
                  )
                : null,
          ),
        ),
      for (final e in embeds)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: EmbedView(embed: e),
          ),
        ),
      if (failed)
        Row(
          spacing: 8,
          children: [
            Text(
              tr('Failed to send'),
              style: TextStyle(fontSize: 12, color: cs.error),
            ),
            _LinkText('Retry', () => store.retryMessage(channelId, m)),
            _LinkText(
              'Delete',
              () => store.discardMessage(channelId, m['nonce'] as String),
            ),
          ],
        ),
      if ((m['reactions'] as Map?)?.isNotEmpty == true ||
          ((m['interactions'] as Map?)?['reactions'] as List?)?.isNotEmpty ==
              true)
        ReactionsBar(message: m),
    ];

    final bodyColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!tail && !compact)
          Padding(
            padding: const EdgeInsets.only(bottom: 0),
            child: Row(
              spacing: 8,
              children: [
                Flexible(child: usernameWidget()),
                ?info,
                if (pronouns != null)
                  Flexible(
                    child: Text(
                      '$pronouns ·',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: infoStyle,
                    ),
                  ),
                Tooltip(
                  message: 'Sent ${formatDateTime(settings, sentAt)}',
                  child: Text(
                    formatCalendar(settings, sentAt),
                    style: infoStyle,
                    maxLines: 1,
                  ),
                ),
                if (editedAt != null)
                  Tooltip(
                    message: 'Edited ${formatDateTime(settings, editedAt)}',
                    child: Text('(edited)', style: infoStyle),
                  ),
              ],
            ),
          ),
        DefaultTextStyle.merge(
          style: base,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: bodyChildren,
          ),
        ),
      ],
    );

    final mentioned = _mentioned(store) && author != store.userId;

    Widget row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        leftColumn,
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: Gap.lg),
            child: bodyColumn,
          ),
        ),
      ],
    );

    Widget tile = Container(
      margin: widget.isLink == MessageLink.none && !tail
          ? EdgeInsets.only(top: settings.messageGroupSpacing)
          : EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        borderRadius: br(Radius_.md),
        color: mentioned
            ? cs.primaryContainer
            : (hover && widget.isLink == MessageLink.none && !editing
                  ? cs.surfaceContainer
                  : Colors.transparent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [?header, row],
      ),
    );

    if (widget.highlight) {
      tile = TweenAnimationBuilder<Color?>(
        tween: ColorTween(
          begin: cs.primary.withValues(alpha: .35),
          end: Colors.transparent,
        ),
        duration: const Duration(seconds: 3),
        builder: (c, v, child) => DecoratedBox(
          decoration: BoxDecoration(color: v, borderRadius: br(Radius_.md)),
          child: child,
        ),
        child: tile,
      );
    }

    if (isLink) {
      return InkWell(
        borderRadius: br(Radius_.md),
        onTap: widget.onTapLink,
        child: IgnorePointer(child: tile),
      );
    }

    final toolbar = (showToolbar && hover && !editing)
        ? Positioned(
            top: widget.isLink == MessageLink.none && !tail
                ? settings.messageGroupSpacing - 18
                : -18,
            right: 16,
            child: MessageToolbar(message: m),
          )
        : null;

    return MouseRegion(
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onSecondaryTapUp: widget.isLink != MessageLink.none || editing
            ? null
            : (d) => showContextMenu(
                context,
                d.globalPosition,
                messageMenu(context, m),
              ),
        onLongPressStart:
            widget.isLink != MessageLink.none || editing || !_isMobile(context)
            ? null
            : (d) {
                HapticFeedback.selectionClick();
                showContextMenu(
                  context,
                  d.globalPosition,
                  messageMenu(context, m),
                );
              },
        child: Stack(clipBehavior: Clip.none, children: [tile, ?toolbar]),
      ),
    );
  }

  static DateTime _safeUlid(String id) {
    try {
      return ulidTime(id);
    } catch (_) {
      return DateTime.now();
    }
  }

  static double _ageDays(DateTime t) =>
      DateTime.now().difference(t).inHours / 24;

  static bool _timedOut(Map? member) {
    final t = member?['timeout'] as String?;
    if (t == null) return false;
    final d = DateTime.tryParse(t);
    return d != null && d.isAfter(DateTime.now());
  }

  static String? _pronouns(Map? member, Map? user) {
    final p = member?['pronouns'] ?? user?['pronouns'];
    if (p is List && p.isNotEmpty) return p.join('/');
    if (p is String && p.isNotEmpty) return p;
    return null;
  }

  Widget _infoIcon(IconData icon, String tip, Color c) => Tooltip(
    message: tip,
    child: Icon(icon, size: 16, color: c),
  );
}

class _LinkText extends StatelessWidget {
  const _LinkText(this.text, this.onTap);
  final String text;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: onTap,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: context.cs.primary,
        ),
      ),
    ),
  );
}

/// Hover toolbar (`MessageToolbar`).
class MessageToolbar extends StatelessWidget {
  const MessageToolbar({super.key, required this.message});
  final Json message;

  @override
  Widget build(BuildContext context) {
    final store = context.read<ClientStore>();
    final cs = context.cs;
    final ch = message['channel'] as String;
    final self = message['author'] == store.userId;
    final shift = HardwareKeyboard.instance.isShiftPressed;

    Widget tool(IconData icon, VoidCallback onTap, {String? tip}) => Tooltip(
      message: tip ?? '',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Gap.sm),
          child: Icon(icon, size: 20, color: cs.onSecondaryContainer),
        ),
      ),
    );

    return Material(
      color: cs.secondaryContainer,
      elevation: 1,
      shadowColor: cs.shadow,
      borderRadius: br(Radius_.xs),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (store.can(ch, Perm.sendMessage))
            tool(
              Icons.reply,
              () => context.read<DraftStore>().addReply(message, store.userId!),
            ),
          if (store.can(ch, Perm.react))
            tool(
              Icons.emoji_emotions_outlined,
              () => reactToMessage(context, message),
            ),
          if (self)
            tool(
              Icons.edit_outlined,
              () => context.read<DraftStore>().setEditing(
                ch,
                message['_id'] as String,
              ),
            ),
          if (self || store.can(ch, Perm.manageMessages))
            tool(
              Icons.delete_outline,
              () => deleteMessageFlow(context, message, quick: shift),
            ),
          Builder(
            builder: (c) => tool(Icons.more_vert, () {
              final box = c.findRenderObject() as RenderBox;
              final p = box.localToGlobal(Offset(0, box.size.height));
              showContextMenu(context, p, messageMenu(context, message));
            }),
          ),
        ],
      ),
    );
  }
}

/// Inline message editor (`EditMessage`).
class InlineEditor extends StatefulWidget {
  const InlineEditor({super.key, required this.message});
  final Json message;
  @override
  State<InlineEditor> createState() => _InlineEditorState();
}

class _InlineEditorState extends State<InlineEditor> {
  late final _ctl = TextEditingController(
    text: widget.message['content'] as String? ?? '',
  );
  final _focus = FocusNode();
  bool saving = false;

  String get ch => widget.message['channel'] as String;

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _cancel() => context.read<DraftStore>().setEditing(ch, null);

  Future<void> _save() async {
    final text = _ctl.text.trim();
    final store = context.read<ClientStore>();
    if (text.isEmpty) {
      await deleteMessageFlow(context, widget.message);
      return;
    }
    if (text == widget.message['content']) {
      _cancel();
      return;
    }
    setState(() => saving = true);
    try {
      await store.editMessage(ch, widget.message['_id'] as String, text);
      if (mounted) _cancel();
    } catch (e) {
      if (mounted) {
        setState(() => saving = false);
        showSnack(context, errorText(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(Gap.md),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: br(Radius_.sm),
          ),
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): _cancel,
              const SingleActivator(LogicalKeyboardKey.enter): _save,
            },
            child: TextField(
              controller: _ctl,
              focusNode: _focus,
              autofocus: true,
              minLines: 1,
              maxLines: 12,
              decoration: const InputDecoration(
                border: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        saving
            ? const Text('Saving message...', style: TextStyle(fontSize: 12))
            : Text.rich(
                TextSpan(
                  style: const TextStyle(fontSize: 12),
                  children: [
                    const TextSpan(text: 'escape to '),
                    _action('cancel', _cancel, cs),
                    const TextSpan(text: ' · enter to '),
                    _action('save', _save, cs),
                  ],
                ),
              ),
      ],
    );
  }

  InlineSpan _action(String t, VoidCallback f, ColorScheme cs) => WidgetSpan(
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: f,
        child: Text(
          t,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: cs.primary,
          ),
        ),
      ),
    ),
  );
}

/// Message being replied to (`MessageReply`).
class MessageReply extends StatefulWidget {
  const MessageReply({
    super.key,
    required this.channelId,
    required this.messageId,
    this.serverId,
    this.mention = false,
    this.noDecorations = false,
  });
  final String channelId, messageId;
  final String? serverId;
  final bool mention, noDecorations;
  @override
  State<MessageReply> createState() => _MessageReplyState();
}

class _MessageReplyState extends State<MessageReply> {
  @override
  void initState() {
    super.initState();
    final store = context.read<ClientStore>();
    if (store.messageById(widget.channelId, widget.messageId) == null) {
      store.fetchMessage(widget.channelId, widget.messageId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final settings = context.watch<SettingsStore>();
    final cs = context.cs;
    final msg = store.messageById(widget.channelId, widget.messageId);
    final author = msg?['author'] as String?;
    final blocked = store.user(author)?['relationship'] == 'Blocked';
    final textStyle = TextStyle(
      fontSize: settings.messageSize,
      color: cs.onSurface,
      height: 1.2,
    );

    Widget body;
    if (blocked) {
      body = Text(tr('Blocked User'), style: textStyle);
    } else if (msg == null) {
      body = Text(tr('Message not loaded, click to jump'), style: textStyle);
    } else {
      final attachments = (msg['attachments'] as List?) ?? const [];
      final content = (msg['content'] as String?) ?? '';
      var short = content.replaceAll('\n', ' ');
      if (short.length > 128) short = '${short.substring(0, 128)}...';
      final masq = msg['masquerade'] as Map?;
      final name =
          (widget.mention ? '@' : '') +
          (masq?['name'] as String? ??
              store.displayName(author, server: widget.serverId));
      final colour =
          parseCssColour(masq?['colour'] as String?) ??
          store.roleColour(author, widget.serverId);
      body = Row(
        spacing: 4,
        children: [
          UserAvatar(userId: author, size: 14),
          Text(
            name,
            maxLines: 1,
            style: textStyle.copyWith(
              fontWeight: FontWeight.w600,
              color: colour ?? cs.onSurface,
            ),
          ),
          const SizedBox(width: 4),
          if (attachments.isNotEmpty)
            Row(
              spacing: 4,
              children: [
                const Icon(Icons.insert_drive_file, size: 16),
                Text(
                  attachments.length > 1
                      ? 'Sent multiple attachments'
                      : 'Sent an attachment',
                  style: textStyle.copyWith(fontStyle: FontStyle.italic),
                ),
              ],
            ),
          if (short.isNotEmpty)
            Flexible(
              child: RichContent(
                short,
                serverId: widget.serverId,
                maxLines: 1,
                disallowBigEmoji: true,
                style: textStyle,
              ),
            ),
        ],
      );
    }

    final border = BorderSide(color: cs.outlineVariant, width: 2);
    return InkWell(
      onTap: () {
        final sid = widget.serverId;
        context.goPath(
          '${sid != null ? '/server/$sid' : ''}/channel/${widget.channelId}/${widget.messageId}',
        );
      },
      child: SizedBox(
        height: settings.messageSize * 1.5,
        child: Row(
          children: [
            if (!widget.noDecorations) ...[
              const SizedBox(width: 30),
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: 22,
                  height: 12,
                  decoration: BoxDecoration(
                    border: Border(left: border, top: border),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: ClipRect(
                child: Align(alignment: Alignment.centerLeft, child: body),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Row of reactions below a message (`Reactions`).
class ReactionsBar extends StatelessWidget {
  const ReactionsBar({super.key, required this.message});
  final Json message;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final cs = context.cs;
    final reactions =
        (message['reactions'] as Map?)?.cast<String, dynamic>() ?? const {};
    final required =
        ((message['interactions'] as Map?)?['reactions'] as List?)
            ?.cast<String>() ??
        const <String>[];
    final optional = reactions.keys
        .where((k) => !required.contains(k))
        .toList();
    if (required.isEmpty && optional.isEmpty) return const SizedBox.shrink();
    final ch = message['channel'] as String;
    final id = message['_id'] as String;

    Widget chip(String key) {
      final users =
          (reactions[key] as List?)?.cast<String>() ?? const <String>[];
      final active = users.contains(store.userId);
      final list = users
          .map((u) => store.user(u)?['username'] as String?)
          .whereType<String>()
          .toList();
      final unknown =
          users.length - list.length + (list.length > 3 ? list.length - 3 : 0);
      final names = list.take(2).join(', ');
      final label = unknown > 0
          ? (names.isNotEmpty
                ? '$names and $unknown others reacted'
                : (unknown == 1 ? '1 person reacted' : '$unknown reacted'))
          : '$names reacted';
      return Tooltip(
        richMessage: WidgetSpan(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 12,
            children: [
              EmojiView(key, size: 48),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  label,
                  maxLines: 2,
                  style: TextStyle(color: cs.onInverseSurface),
                ),
              ),
            ],
          ),
        ),
        child: Material(
          color: active ? cs.secondaryContainer : cs.surfaceContainerLow,
          borderRadius: br(Radius_.md),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => store.react(ch, id, key, !active),
            child: Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 8,
                children: [
                  EmojiView(key, size: 17),
                  Text(
                    '${users.length}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: active ? cs.onSecondaryContainer : cs.onSurface,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return _HoverReveal(
      builder: (hovering) => Wrap(
        spacing: Gap.sm,
        runSpacing: Gap.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final k in required) chip(k),
          if (required.isNotEmpty && optional.isNotEmpty)
            Container(width: 1, height: 14, color: cs.outlineVariant),
          for (final k in optional) chip(k),
          Opacity(
            opacity: hovering ? 1 : 0,
            child: Material(
              color: cs.surfaceBright,
              borderRadius: br(Radius_.md),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: store.can(ch, Perm.react)
                    ? () => reactToMessage(context, message)
                    : null,
                child: const SizedBox(
                  width: 33,
                  height: 33,
                  child: Icon(Icons.add, size: 18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HoverReveal extends StatefulWidget {
  const _HoverReveal({required this.builder});
  final Widget Function(bool hovering) builder;
  @override
  State<_HoverReveal> createState() => _HoverRevealState();
}

class _HoverRevealState extends State<_HoverReveal> {
  bool h = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => h = true),
    onExit: (_) => setState(() => h = false),
    child: widget.builder(h || _isMobile(context)),
  );
}

// ----- system messages -----

(IconData, bool) _systemIcon(String type, bool isServer) {
  switch (type) {
    case 'user_added':
      return (Icons.add, false);
    case 'user_left':
      return isServer ? (Icons.arrow_back, true) : (Icons.remove, true);
    case 'user_remove':
      return (Icons.close, false);
    case 'user_kicked':
      return (Icons.cancel, true);
    case 'user_banned':
      return (Icons.gpp_bad, true);
    case 'user_joined':
      return (Icons.arrow_forward, false);
    case 'channel_renamed':
      return (Icons.sell, false);
    case 'channel_description_changed':
      return (Icons.notes, false);
    case 'channel_icon_changed':
      return (Icons.image, false);
    case 'channel_ownership_changed':
      return (Icons.key, false);
    case 'message_pinned':
    case 'message_unpinned':
      return (Icons.push_pin_outlined, false);
    case 'call_started':
      return (Icons.phone_outlined, false);
    default:
      return (Icons.info, false);
  }
}

class SystemMessageIcon extends StatelessWidget {
  const SystemMessageIcon({
    super.key,
    required this.type,
    required this.sentAt,
    required this.isServer,
  });
  final String type;
  final DateTime sentAt;
  final bool isServer;
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final (icon, error) = _systemIcon(type, isServer);
    return SizedBox(
      width: 62,
      height: 24,
      child: Tooltip(
        message: formatRelative(sentAt),
        child: Icon(icon, size: 16, color: error ? cs.error : cs.primary),
      ),
    );
  }
}

class SystemMessageView extends StatelessWidget {
  const SystemMessageView({
    super.key,
    required this.system,
    required this.isServer,
    required this.channelId,
    required this.serverId,
    required this.sentAt,
  });
  final Map system;
  final bool isServer;
  final String channelId;
  final String? serverId;
  final DateTime sentAt;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final settings = context.watch<SettingsStore>();
    String? s(String k) => system[k] as String?;
    Widget user(String? id) => id == null
        ? const Text('Unknown User')
        : UserMention(userId: id, serverId: serverId);
    List<InlineSpan> parts(List<Object?> items) => [
      for (final i in items)
        if (i is String)
          TextSpan(text: i)
        else if (i is Widget)
          WidgetSpan(alignment: PlaceholderAlignment.middle, child: i),
    ];

    List<InlineSpan> spans;
    switch (system['type']) {
      case 'user_added':
        spans = parts([user(s('id')), ' has been added by ', user(s('by'))]);
      case 'user_left':
        spans = parts([
          user(s('id')),
          isServer ? ' left the server' : ' left the group',
        ]);
      case 'user_remove':
        spans = parts([user(s('id')), ' has been removed by ', user(s('by'))]);
      case 'user_kicked':
        spans = parts([user(s('id')), ' has been kicked from the server']);
      case 'user_banned':
        spans = parts([user(s('id')), ' has been banned from the server']);
      case 'user_joined':
        spans = parts([user(s('id')), ' joined the server']);
      case 'channel_renamed':
        spans = [
          ...parts([user(s('by')), ' updated the group name to ']),
          TextSpan(
            text: s('name') ?? '',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ];
      case 'channel_description_changed':
        spans = parts([user(s('by')), ' updated the group description']);
      case 'channel_icon_changed':
        spans = parts([user(s('by')), ' updated the group icon ']);
      case 'channel_ownership_changed':
        spans = parts([
          user(s('from')),
          ' transferred group ownership to ',
          user(s('to')),
        ]);
      case 'message_pinned':
      case 'message_unpinned':
        final id = s('id');
        spans = [
          ...parts([
            user(s('by')),
            system['type'] == 'message_pinned' ? ' pinned ' : ' unpinned ',
          ]),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => context.goPath(
                  '${serverId != null ? '/server/$serverId' : ''}/channel/$channelId/$id',
                ),
                child: Text('a message', style: TextStyle(color: cs.primary)),
              ),
            ),
          ),
        ];
      case 'call_started':
        final finished = s('finished_at') != null
            ? DateTime.tryParse(s('finished_at')!)?.toLocal()
            : null;
        if (finished == null) {
          spans = parts([user(s('by')), ' started a call']);
        } else {
          spans = [
            ...parts([user(s('by')), ' started a call that lasted ']),
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Tooltip(
                message: formatDateTime(settings, finished),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: br(Radius_.sm),
                  ),
                  child: Text(
                    formatRelative(
                      finished,
                      reference: sentAt,
                      hideSuffix: true,
                    ),
                  ),
                ),
              ),
            ),
          ];
        }
      case 'text':
        spans = [TextSpan(text: s('content') ?? '')];
      default:
        spans = [TextSpan(text: '${system['type']}')];
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 20),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text.rich(TextSpan(children: spans)),
      ),
    );
  }
}

// ----- list helpers -----

class MessageDivider extends StatelessWidget {
  const MessageDivider({super.key, this.date, this.unread = false});
  final String? date;
  final bool unread;
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final line = unread ? cs.primary : cs.outlineVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 17, 12, 17),
      child: Row(
        children: [
          if (unread)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: cs.primary,
                borderRadius: BorderRadius.circular(60),
              ),
              child: Text(
                tr('NEW'),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: cs.onPrimary,
                ),
              ),
            ),
          if (date != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                borderRadius: br(Radius_.md),
              ),
              child: Text(
                date!,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: cs.outline,
                ),
              ),
            ),
          Expanded(child: Container(height: 1, color: line)),
        ],
      ),
    );
  }
}

class ConversationStart extends StatelessWidget {
  const ConversationStart({super.key, required this.channel});
  final Json channel;
  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final cs = context.cs;
    final saved = channel['channel_type'] == 'SavedMessages';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!saved)
            Text(
              store.channelName(channel),
              style: TextStyle(fontSize: 32, color: cs.onSurface),
            ),
          Text(
            saved
                ? 'This is the start of your notes.'
                : 'This is the start of your conversation.',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class BlockedMessages extends StatelessWidget {
  const BlockedMessages({super.key, required this.count});
  final int count;
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(64, 8, 0, 4),
      child: Row(
        spacing: 6,
        children: [
          Icon(Icons.close, size: 16, color: cs.outline),
          Text(
            '$count blocked ${count == 1 ? 'message' : 'messages'}',
            style: TextStyle(fontSize: 12, color: cs.outline),
          ),
        ],
      ),
    );
  }
}
