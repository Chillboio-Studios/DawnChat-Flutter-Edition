import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../net_image.dart';

import 'package:markdown/markdown.dart' as md;
import 'package:provider/provider.dart';

import '../../api/client_store.dart';
import '../../core/css_colour.dart';
import '../../core/links.dart';
import '../../router.dart';
import '../../state/settings_store.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../menus/context_menu.dart';
import '../menus/user_menu.dart';
import '../widgets.dart';
import 'time_utils.dart';
import '../../core/i18n.dart';

const _emojiPattern =
    r'(?:[\u{1F1E6}-\u{1F1FF}]{2}|[0-9#*]\uFE0F?\u20E3|(?:[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{2190}-\u{21FF}\u{2300}-\u{23FF}\u{00A9}\u{00AE}\u{203C}\u{2049}\u{2122}\u{2139}\u{3030}\u{303D}\u{3297}\u{3299}][\u{1F3FB}-\u{1F3FF}]?\uFE0F?(?:\u200D[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{2640}\u{2642}][\u{1F3FB}-\u{1F3FF}]?\uFE0F?)*))';

final _onlyEmojiRe = RegExp(
  r'^(?:\s|:[0-9A-Z]{26}:|' + _emojiPattern + r')+$',
  unicode: true,
);
final _anyEmojiRe = RegExp(r':[0-9A-Z]{26}:|' + _emojiPattern, unicode: true);

String unicodeEmojiUrl(String pack, String emoji) {
  final cps = emoji.runes.map((r) => r.toRadixString(16)).join('-');
  return '$unicodeEmojiBaseUrl/$pack/$cps.svg?v=1';
}

/// A reaction/emoji key: 26 char ULID = custom emoji, otherwise unicode.
class EmojiView extends StatelessWidget {
  const EmojiView(this.emoji, {super.key, this.size = 20});
  final String emoji;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (emoji.length == 26 && RegExp(r'^[0-9A-Z]{26}$').hasMatch(emoji)) {
      final store = context.read<ClientStore>();
      return Tooltip(
        message: ':${store.emojis[emoji]?['name'] ?? emoji}:',
        child: NetImage(
          '$customEmojiBaseUrl/$emoji',
          height: size,
          width: size,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      );
    }
    // Drop variation selector like the web client's pack lookup.
    final key = emoji.replaceAll('\uFE0F', '');
    return NetSvg(
      unicodeEmojiUrl(
        context.read<SettingsStore>().unicodeEmoji,
        key.isEmpty ? emoji : key,
      ),
      height: size,
      width: size,
      placeholderBuilder: (_) => SizedBox(width: size, height: size),
      errorBuilder: (_, _, _) =>
          Text(emoji, style: TextStyle(fontSize: size * .8)),
    );
  }
}

class _Syn extends md.InlineSyntax {
  _Syn(super.pattern, this.tag) : super(startCharacter: null);
  final String tag;
  final int group = 1;
  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final el = md.Element.text(tag, match.group(group) ?? match.group(0)!);
    el.attributes['raw'] = match.group(0)!;
    if (match.groupCount >= 2 && match.group(2) != null)
      el.attributes['arg'] = match.group(2)!;
    parser.addNode(el);
    return true;
  }
}

/// Unicode emoji syntax; the markdown package compiles patterns without the unicode flag.
class _EmojiSyn extends md.InlineSyntax {
  _EmojiSyn() : super('x');
  static final _re = RegExp(_emojiPattern, unicode: true);

  @override
  bool tryMatch(md.InlineParser parser, [int? startMatchPos]) {
    final m = _re.matchAsPrefix(parser.source, startMatchPos ?? parser.pos);
    if (m == null) return false;
    parser.writeText();
    if (onMatch(parser, m)) parser.consume(m[0]!.length);
    return true;
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final el = md.Element.text('uemoji', match.group(0)!);
    parser.addNode(el);
    return true;
  }
}

final _document = md.Document(
  extensionSet: md.ExtensionSet.gitHubFlavored,
  encodeHtml: false,
  inlineSyntaxes: [
    _Syn(r'\|\|(.+?)\|\|', 'spoiler'),
    _Syn(r'<t:([0-9]+)(?::(\w))?>', 'time'),
    _Syn(r'<@([0-9A-HJKMNP-TV-Z]{26})>', 'user'),
    _Syn(r'<%([0-9A-HJKMNP-TV-Z]{26})>', 'role'),
    _Syn(r'<#([0-9A-HJKMNP-TV-Z]{26})>', 'channel'),
    _Syn(r'@(everyone|online)\b', 'special'),
    _Syn(r':([0-9A-HJKMNP-TV-Z]{26}):', 'emoji'),
    _EmojiSyn(),
  ],
);

/// Internal route extracted from a URL pointing at an in-app origin.
class _InApp {
  _InApp(
    this.host,
    this.server,
    this.channel,
    this.message,
    this.invite,
    this.bot,
    this.discover,
  );
  final String host;
  final String? server, channel, message, invite, bot;
  final bool discover;
}

_InApp? parseInApp(String href, String instanceOrigin) {
  final u = Uri.tryParse(href);
  if (u == null || !u.hasAuthority) return null;
  var path = u.path;
  var host = u.host;
  if (u.origin == discoverUrl ||
      u.origin == inviteShortenerUrl.replaceFirst(RegExp(r'/dc/$'), '')) {
    final m = RegExp(r'^/(?:dc/+)?([\w\d]+)/?$').firstMatch(path);
    if (m != null && !path.startsWith('/discover')) {
      return _InApp(dawnchatHost, null, null, null, m.group(1), null, false);
    }
    if (path.startsWith('/discover'))
      return _InApp(dawnchatHost, null, null, null, null, null, true);
    return null;
  }
  const inApp = [
    dawnchatChatUrl,
    'https://dawn-chat.com',
    'https://csinvite.net',
    dawnchatAppUrl,
  ];
  if (![instanceOrigin, ...inApp].contains(u.origin)) return null;
  if (!RegExp(r'/(i|app|home|pwa|dev|invite|bot|friends|server|channel)/?')
      .hasMatch(path))
    return null;
  final im = RegExp(r'^/i/([^/]+)').firstMatch(path);
  if (im != null) {
    host = im.group(1)!;
    path = path.substring(im.end);
  } else {
    host = dawnchatHost;
  }
  final seg = path.split('/').where((e) => e.isNotEmpty).toList();
  String? server, channel, message, invite, bot;
  for (var i = 0; i < seg.length; i++) {
    if (seg[i] == 'server' && i + 1 < seg.length) server = seg[i + 1];
    if (seg[i] == 'channel' && i + 1 < seg.length) {
      channel = seg[i + 1];
      if (i + 2 < seg.length) message = seg[i + 2];
    }
    if (seg[i] == 'invite' && i + 1 < seg.length) invite = seg[i + 1];
    if (seg[i] == 'bot' && i + 1 < seg.length) bot = seg[i + 1];
  }
  return _InApp(
    host,
    server,
    channel,
    message,
    invite,
    bot,
    seg.contains('discover'),
  );
}

/// Opens a link, applying the client's link-safety rules.
Future<void> handleLink(
  BuildContext context,
  String href, {
  String? display,
}) async {
  final store = context.read<ClientStore>();
  final settings = context.read<SettingsStore>();
  final u = Uri.tryParse(href);
  if (u == null) return;
  if (!{'http', 'https', 'mailto', 'tel'}.contains(u.scheme)) return;

  final origin = 'https://${store.host ?? dawnchatHost}';
  final inApp = parseInApp(href, origin);
  if (inApp != null && inApp.host == (store.host ?? dawnchatHost)) {
    if (inApp.invite != null) return context.goPath('/invite/${inApp.invite}');
    if (inApp.bot != null) return context.goPath('/bot/${inApp.bot}');
    if (inApp.discover) return context.goPath('/discover');
    if (inApp.channel != null) {
      final sid = inApp.server ?? store.channels[inApp.channel]?['server'];
      return context.goPath(
        '${sid != null ? '/server/$sid' : ''}/channel/${inApp.channel}${inApp.message != null ? '/${inApp.message}' : ''}',
      );
    }
    if (inApp.server != null) return context.goPath('/server/${inApp.server}');
  }

  if (u.scheme == 'mailto' || u.scheme == 'tel' || settings.isTrusted(u))
    return openUrl(href);
  await showLinkWarning(context, u, display ?? href);
}

Future<void> showLinkWarning(
  BuildContext context,
  Uri url,
  String display,
) async {
  final settings = context.read<SettingsStore>();
  var scrutiny = 0;
  if (url.toString() != display) {
    final d = Uri.tryParse(display);
    scrutiny = (d != null && d.hasAuthority && d.toString() != url.toString())
        ? 2
        : 1;
  }
  var checked = false;
  final go = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text(tr('External links can be dangerous!')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Are you sure you want to go to '),
                  TextSpan(
                    text: url.toString(),
                    style: const TextStyle(
                      decoration: TextDecoration.underline,
                    ),
                  ),
                  const TextSpan(text: '?'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (scrutiny == 1) Text('You clicked on "$display"'),
            if (scrutiny == 2) ...[
              Text(
                'Be careful!',
                style: TextStyle(
                  color: c.cs.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                display,
                style: TextStyle(
                  color: c.cs.error,
                  decoration: TextDecoration.underline,
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: checked,
                onChanged: (v) => set(() => checked = v ?? false),
                title: Text(tr('I understand the consequences')),
              ),
            ] else
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: checked,
                onChanged: (v) => set(() => checked = v ?? false),
                title: Text("Don't ask me again for ${url.origin}"),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(tr('Close')),
          ),
          FilledButton(
            onPressed: (scrutiny == 2 && !checked)
                ? null
                : () => Navigator.pop(c, true),
            child: Text(tr('Continue')),
          ),
        ],
      ),
    ),
  );
  if (go == true) {
    await openUrl(url.toString());
    if (checked && scrutiny == 0) settings.trustOrigin(url);
  }
}

/// Markdown renderer for chat content (remark pipeline of the web client).
class RichContent extends StatefulWidget {
  const RichContent(
    this.content, {
    super.key,
    this.serverId,
    this.maxLines,
    this.disallowBigEmoji = false,
    this.style,
  });
  final String content;
  final String? serverId;
  final int? maxLines;
  final bool disallowBigEmoji;
  final TextStyle? style;

  @override
  State<RichContent> createState() => _RichContentState();
}

class _RichContentState extends State<RichContent> {
  final List<GestureRecognizer> _recognizers = [];

  void _clear() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  TapGestureRecognizer _tap(VoidCallback fn) {
    final r = TapGestureRecognizer()..onTap = fn;
    _recognizers.add(r);
    return r;
  }

  @override
  Widget build(BuildContext context) {
    _clear();
    final store = context.watch<ClientStore>();
    final settings = context.watch<SettingsStore>();
    final cs = context.cs;
    final content = widget.content;

    final onlyEmoji =
        !widget.disallowBigEmoji &&
        content.trim().isNotEmpty &&
        _onlyEmojiRe.hasMatch(content);
    final emojiCount = onlyEmoji ? _anyEmojiRe.allMatches(content).length : 0;
    final base =
        widget.style ??
        TextStyle(
          fontSize: settings.messageSize,
          height: 1.4,
          color: cs.onSurface,
        );
    final emojiSize = onlyEmoji
        ? (emojiCount > 1 ? 48.0 : 96.0)
        : (base.fontSize ?? 14) * 1.4;

    final nodes = _document.parseLines(content.split('\n'));
    final ctx = _Ctx(
      context,
      store,
      settings,
      cs,
      emojiSize,
      _tap,
      widget.serverId,
    );

    if (widget.maxLines != null) {
      final spans = <InlineSpan>[];
      for (final n in nodes) {
        spans.addAll(_plain(n, ctx, base));
        spans.add(const TextSpan(text: ' '));
      }
      return Text.rich(
        TextSpan(children: spans, style: base),
        maxLines: widget.maxLines,
        overflow: TextOverflow.ellipsis,
      );
    }

    final blocks = _blocks(nodes, ctx, base);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: blocks,
    );
  }
}

class _Ctx {
  _Ctx(
    this.context,
    this.store,
    this.settings,
    this.cs,
    this.emojiSize,
    this.tap,
    this.serverId,
  );
  final BuildContext context;
  final ClientStore store;
  final SettingsStore settings;
  final ColorScheme cs;
  final double emojiSize;
  final TapGestureRecognizer Function(VoidCallback) tap;
  final String? serverId;
}

List<InlineSpan> _plain(md.Node n, _Ctx c, TextStyle base) {
  if (n is md.Text) return [TextSpan(text: n.text.replaceAll('\n', ' '))];
  if (n is md.Element) {
    if (n.tag == 'pre') return const [TextSpan(text: '[code]')];
    if (n.tag == 'img') return [TextSpan(text: n.attributes['alt'] ?? '')];
    final children = n.children ?? const <md.Node>[];
    if (_customTags.contains(n.tag)) return _inlineElement(n, c, base);
    return [for (final ch in children) ..._plain(ch, c, base)];
  }
  return const [];
}

const _customTags = {
  'spoiler',
  'time',
  'user',
  'role',
  'channel',
  'special',
  'emoji',
  'uemoji',
};

List<Widget> _blocks(List<md.Node> nodes, _Ctx c, TextStyle base) {
  final out = <Widget>[];
  for (final n in nodes) {
    if (n is md.Text) {
      if (n.text.trim().isNotEmpty) out.add(_para([n], c, base));
      continue;
    }
    final e = n as md.Element;
    final children = e.children ?? const <md.Node>[];
    switch (e.tag) {
      case 'p':
        out.add(_para(children, c, base));
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        final size = switch (e.tag) {
          'h1' => 2.0,
          'h2' => 1.6,
          'h3' => 1.35,
          'h4' => 1.15,
          _ => 1.0,
        };
        out.add(
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 2),
            child: _para(
              children,
              c,
              base.copyWith(
                fontSize: (base.fontSize ?? 14) * size,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      case 'blockquote':
        out.add(
          Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: c.cs.outlineVariant, width: 4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _blocks(children, c, base),
            ),
          ),
        );
      case 'ul' || 'ol':
        var i = 0;
        for (final li in children.whereType<md.Element>()) {
          i++;
          final marker = e.tag == 'ul' ? '•' : '$i.';
          final task = li.children
              ?.whereType<md.Element>()
              .where((x) => x.tag == 'input')
              .firstOrNull;
          out.add(
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 22,
                    child: task != null
                        ? Icon(
                            task.attributes['checked'] == 'true'
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                            size: 16,
                          )
                        : Text(marker, style: base),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _liContent(li, c, base),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      case 'pre':
        final code = e.children?.whereType<md.Element>().firstOrNull;
        final text = (code?.textContent ?? e.textContent).trimRight();
        out.add(
          _CodeBlock(
            text: text,
            lang: (code?.attributes['class'] ?? '').replaceFirst(
              'language-',
              '',
            ),
            settings: c.settings,
          ),
        );
      case 'hr':
        out.add(Divider(color: c.cs.outlineVariant));
      case 'table':
        out.add(_table(e, c, base));
      default:
        out.add(_para(children, c, base));
    }
  }
  return out;
}

List<Widget> _liContent(md.Element li, _Ctx c, TextStyle base) {
  final children = li.children ?? const <md.Node>[];
  final hasBlock = children.any(
    (x) =>
        x is md.Element &&
        const {'p', 'ul', 'ol', 'pre', 'blockquote'}.contains(x.tag),
  );
  if (!hasBlock) {
    return [
      _para(
        children.where((x) => !(x is md.Element && x.tag == 'input')).toList(),
        c,
        base,
      ),
    ];
  }
  return _blocks(children, c, base);
}

Widget _table(md.Element t, _Ctx c, TextStyle base) {
  final rows = <TableRow>[];
  for (final section in t.children!.whereType<md.Element>()) {
    for (final tr in section.children!.whereType<md.Element>()) {
      rows.add(
        TableRow(
          children: [
            for (final cell in tr.children!.whereType<md.Element>())
              Padding(
                padding: const EdgeInsets.all(6),
                child: _para(
                  cell.children ?? const [],
                  c,
                  cell.tag == 'th'
                      ? base.copyWith(fontWeight: FontWeight.w700)
                      : base,
                ),
              ),
          ],
        ),
      );
    }
  }
  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Table(
      defaultColumnWidth: const IntrinsicColumnWidth(),
      border: TableBorder.all(color: c.cs.outlineVariant),
      children: rows,
    ),
  );
}

Widget _para(List<md.Node> nodes, _Ctx c, TextStyle base) {
  final spans = _inline(nodes, c, base);
  if (spans.isEmpty) return const SizedBox.shrink();
  return Text.rich(TextSpan(children: spans, style: base));
}

List<InlineSpan> _inline(List<md.Node> nodes, _Ctx c, TextStyle base) {
  final out = <InlineSpan>[];
  for (final n in nodes) {
    if (n is md.Text) {
      out.add(TextSpan(text: n.text));
    } else if (n is md.Element) {
      out.addAll(_inlineElement(n, c, base));
    }
  }
  return out;
}

List<InlineSpan> _inlineElement(md.Element e, _Ctx c, TextStyle base) {
  final children = e.children ?? const <md.Node>[];
  final cs = c.cs;
  switch (e.tag) {
    case 'em':
      return [
        TextSpan(
          children: _inline(children, c, base),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ),
      ];
    case 'strong':
      return [
        TextSpan(
          children: _inline(children, c, base),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ];
    case 'del':
      return [
        TextSpan(
          children: _inline(children, c, base),
          style: const TextStyle(decoration: TextDecoration.lineThrough),
        ),
      ];
    case 'code':
      return [
        TextSpan(
          text: e.textContent,
          style: monoStyle(
            c.settings,
            TextStyle(
              backgroundColor: cs.surfaceContainerHighest,
              fontSize: (base.fontSize ?? 14) - 1,
            ),
          ),
        ),
      ];
    case 'br':
      return [const TextSpan(text: '\n')];
    case 'img':
      return [TextSpan(text: e.attributes['alt'] ?? '')];
    case 'a':
      final href = e.attributes['href'] ?? '';
      final text = e.textContent;
      return _anchor(c, href, text, children, base);
    case 'spoiler':
      return [
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: _Spoiler(text: e.textContent, style: base),
        ),
      ];
    case 'time':
      final unix = int.tryParse(e.textContent) ?? 0;
      return [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _Timestamp(
            unix: unix,
            format: e.attributes['arg'],
            style: base,
          ),
        ),
      ];
    case 'user':
      return [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: UserMention(userId: e.textContent, serverId: c.serverId),
        ),
      ];
    case 'role':
      return [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _RoleMention(roleId: e.textContent, serverId: c.serverId),
        ),
      ];
    case 'special':
      return [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _Pill(icon: Icons.alternate_email, label: e.textContent),
        ),
      ];
    case 'channel':
      final ch = c.store.channels[e.textContent];
      return [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: InkWell(
            borderRadius: br(Radius_.lg),
            onTap: ch == null
                ? null
                : () => handleLink(
                    c.context,
                    '$dawnchatChatUrl${ch['server'] != null ? '/server/${ch['server']}' : ''}/channel/${ch['_id']}',
                  ),
            child: _Pill(
              icon: Icons.tag,
              label: ch?['name'] as String? ?? 'Unknown Channel',
              primary: true,
            ),
          ),
        ),
      ];
    case 'emoji':
      return [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Tooltip(
            message:
                ':${c.store.emojis[e.textContent]?['name'] ?? e.textContent}:',
            child: NetImage(
              '$customEmojiBaseUrl/${e.textContent}',
              height: c.emojiSize,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ),
      ];
    case 'uemoji':
      final em = e.textContent;
      return [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: EmojiView(em, size: c.emojiSize),
        ),
      ];
    default:
      return _inline(children, c, base);
  }
}

List<InlineSpan> _anchor(
  _Ctx c,
  String href,
  String text,
  List<md.Node> children,
  TextStyle base,
) {
  final cs = c.cs;
  final u = Uri.tryParse(href);
  if (href.isEmpty || u == null) return [TextSpan(text: text)];
  if (!{'http', 'https', 'mailto', 'tel'}.contains(u.scheme))
    return [TextSpan(text: text)];

  final origin = 'https://${c.store.host ?? dawnchatHost}';
  final inApp = parseInApp(href, origin);
  if (inApp != null) {
    final remote = inApp.host != (c.store.host ?? dawnchatHost);
    if (inApp.channel != null) {
      final ch = c.store.channels[inApp.channel];
      if (!remote && ch == null)
        return [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _Pill(
              icon: Icons.tag,
              label: tr('Private Channel'),
              primary: true,
            ),
          ),
        ];
      return [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: InkWell(
            borderRadius: br(Radius_.lg),
            onTap: () => remote ? openUrl(href) : handleLink(c.context, href),
            child: _Pill(
              icon: Icons.tag,
              label: remote ? 'Remote Channel' : (ch?['name'] as String? ?? ''),
              primary: true,
              trailing: inApp.message != null
                  ? const [
                      Icon(Icons.chevron_right, size: 14),
                      Icon(Icons.chat, size: 14),
                    ]
                  : const [],
            ),
          ),
        ),
      ];
    }
    if (inApp.server != null) {
      final s = c.store.servers[inApp.server];
      if (!remote && s == null)
        return [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _Pill(
              icon: Icons.people,
              label: tr('Unknown Server'),
              primary: true,
            ),
          ),
        ];
      return [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: InkWell(
            borderRadius: br(Radius_.lg),
            onTap: () => remote ? openUrl(href) : handleLink(c.context, href),
            child: _Pill(
              icon: Icons.people,
              label: remote ? 'Remote Server' : (s?['name'] as String? ?? ''),
              primary: true,
            ),
          ),
        ),
      ];
    }
    if (inApp.invite != null && text == href) {
      return [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: InviteEmbed(code: inApp.invite!),
        ),
      ];
    }
  }
  return [
    TextSpan(
      children: _inline(children, c, base),
      style: TextStyle(color: cs.primary),
      recognizer: c.tap(() => handleLink(c.context, href, display: text)),
    ),
  ];
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    this.primary = false,
    this.trailing = const [],
  });
  final IconData icon;
  final String label;
  final bool primary;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final bg = primary ? cs.primary : cs.primaryContainer;
    final fg = primary ? cs.onPrimary : cs.onPrimaryContainer;
    return Container(
      padding: const EdgeInsets.only(left: 4, right: 6),
      decoration: BoxDecoration(color: bg, borderRadius: br(Radius_.lg)),
      child: IconTheme(
        data: IconThemeData(color: fg, size: 14),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: fg, fontWeight: FontWeight.w600),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: [
              Icon(icon),
              Flexible(child: Text(tr(label), overflow: TextOverflow.ellipsis)),
              ...trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class UserMention extends StatelessWidget {
  const UserMention({super.key, required this.userId, this.serverId});
  final String userId;
  final String? serverId;
  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final cs = context.cs;
    final u = store.user(userId);
    if (u == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: br(Radius_.lg),
        ),
        child: Text(
          'Unknown User',
          style: TextStyle(
            color: cs.onPrimaryContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    return GestureDetector(
      onSecondaryTapUp: (d) => showContextMenu(
        context,
        d.globalPosition,
        userMenu(context, userId, serverId: serverId),
      ),
      onLongPressStart: (d) => showContextMenu(
        context,
        d.globalPosition,
        userMenu(context, userId, serverId: serverId),
      ),
      child: InkWell(
        borderRadius: br(Radius_.lg),
        onTap: () => openUserCard(context, userId, serverId: serverId),
        child: Container(
          padding: const EdgeInsets.only(left: 2, right: 6),
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: br(Radius_.lg),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: [
              UserAvatar(userId: userId, size: 16),
              Flexible(
                child: Text(
                  store.displayName(userId, server: serverId),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color:
                        store.roleColour(userId, serverId) ??
                        cs.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleMention extends StatelessWidget {
  const _RoleMention({required this.roleId, this.serverId});
  final String roleId;
  final String? serverId;
  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final cs = context.cs;
    final role = ((store.servers[serverId]?['roles'] as Map?)?[roleId]) as Map?;
    if (role == null)
      return const _Pill(icon: Icons.circle, label: 'Unknown Role');
    final colour =
        parseCssColour(role['colour'] as String?) ?? cs.outlineVariant;
    return Container(
      padding: const EdgeInsets.only(left: 2, right: 6),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: br(Radius_.lg),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          Container(
            width: 14,
            height: 14,
            margin: const EdgeInsets.all(1),
            decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
          ),
          Text(
            role['name'] as String? ?? '',
            style: TextStyle(color: colour, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _Timestamp extends StatelessWidget {
  const _Timestamp({
    required this.unix,
    required this.format,
    required this.style,
  });
  final int unix;
  final String? format;
  final TextStyle style;
  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    final cs = context.cs;
    final d = DateTime.fromMillisecondsSinceEpoch(unix * 1000);
    String two(int v) => v.toString().padLeft(2, '0');
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    const wd = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final dl = d.toLocal();
    final text = switch (format) {
      't' => '${two(dl.hour % 12 == 0 ? 12 : dl.hour % 12)}:${two(dl.minute)}',
      'T' =>
        '${two(dl.hour % 12 == 0 ? 12 : dl.hour % 12)}:${two(dl.minute)}:${two(dl.second)}',
      'R' => formatRelative(d),
      'D' => '${two(dl.day)} ${months[dl.month - 1]} ${dl.year}',
      'F' =>
        '${wd[dl.weekday - 1]}, ${two(dl.day)} ${months[dl.month - 1]} ${dl.year} ${two(dl.hour % 12 == 0 ? 12 : dl.hour % 12)}:${two(dl.minute)}',
      'f' =>
        '${two(dl.day)} ${months[dl.month - 1]} ${dl.year} ${two(dl.hour % 12 == 0 ? 12 : dl.hour % 12)}:${two(dl.minute)}',
      _ => formatDateTime(s, d),
    };
    return Tooltip(
      message: dl.toString(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: br(Radius_.sm),
        ),
        child: Text(text, style: style),
      ),
    );
  }
}

class _Spoiler extends StatefulWidget {
  const _Spoiler({required this.text, required this.style});
  final String text;
  final TextStyle style;
  @override
  State<_Spoiler> createState() => _SpoilerState();
}

class _SpoilerState extends State<_Spoiler> {
  bool _shown = false;
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return GestureDetector(
      onTap: () => setState(() => _shown = !_shown),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: _shown ? cs.surfaceContainerHighest : cs.onSurface,
          borderRadius: br(Radius_.xs),
        ),
        child: Text(
          widget.text,
          style: widget.style.copyWith(
            color: _shown ? cs.onSurface : Colors.transparent,
          ),
        ),
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({
    required this.text,
    required this.lang,
    required this.settings,
  });
  final String text, lang;
  final SettingsStore settings;
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: br(Radius_.sm),
      ),
      child: Stack(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(10),
            child: SelectableText(
              text,
              style: monoStyle(
                settings,
                TextStyle(
                  fontSize: settings.messageSize - 1,
                  color: const Color(0xFFC9D1D9),
                ),
              ),
            ),
          ),
          Positioned(
            right: 2,
            top: 2,
            child: IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.copy, size: 16, color: cs.outline),
              tooltip: lang.isEmpty ? 'Copy' : 'Copy $lang',
              onPressed: () => copyText(context, text),
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline invite card (`Invite` element).
class InviteEmbed extends StatefulWidget {
  const InviteEmbed({super.key, required this.code});
  final String code;
  @override
  State<InviteEmbed> createState() => _InviteEmbedState();
}

class _InviteEmbedState extends State<InviteEmbed> {
  Map<String, dynamic>? _invite;
  bool _failed = false, _busy = false;

  @override
  void initState() {
    super.initState();
    context
        .read<ClientStore>()
        .fetchInvite(widget.code)
        .then((r) {
          if (mounted) setState(() => _invite = r);
        })
        .catchError((_) {
          if (mounted) setState(() => _failed = true);
        });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final cs = context.cs;
    final inv = _invite;
    if (_failed)
      return const _Pill(icon: Icons.link_off, label: 'Invalid invite');
    final joined = inv != null && store.servers.containsKey(inv['server_id']);
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      height: 64,
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: br(Radius_.md),
      ),
      child: inv == null
          ? const Center(child: CircularProgressIndicator())
          : Row(
              spacing: Gap.md,
              children: [
                IconAvatar(
                  url: store.api.fileUrl(
                    'icons',
                    inv['server_icon'] as Map?,
                    width: 84,
                  ),
                  name: inv['server_name'] as String? ?? '?',
                  size: 42,
                  square: false,
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        inv['server_name'] as String? ?? '',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: cs.onSecondaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${inv['member_count']} members',
                        style: TextStyle(
                          color: cs.onSecondaryContainer.withValues(alpha: .7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: joined || _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          try {
                            final res = await store.joinInvite(widget.code);
                            final server = res['server'] as Map?;
                            if (server != null) {
                              store.servers[server['_id']] = server
                                  .cast<String, dynamic>();
                              for (final ch
                                  in (res['channels'] as List? ?? [])) {
                                store.channels[ch['_id']] = (ch as Map)
                                    .cast<String, dynamic>();
                              }
                              store.refresh();
                              if (context.mounted)
                                context.goPath('/server/${server['_id']}');
                            }
                          } catch (e) {
                            if (context.mounted)
                              showSnack(context, errorText(e));
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                  child: Text(joined ? 'Joined' : 'Join'),
                ),
              ],
            ),
    );
  }
}
