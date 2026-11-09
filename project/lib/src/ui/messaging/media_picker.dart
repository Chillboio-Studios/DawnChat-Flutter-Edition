import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import '../net_image.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../api/client_store.dart';
import '../../core/emoji_data.dart';
import '../../core/links.dart';
import '../../state/settings_store.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../widgets.dart';
import 'embeds.dart';
import 'markdown_view.dart';
import '../../core/i18n.dart';

const _klipyKey = String.fromEnvironment('KLIPY_API_KEY');
const _gifboxDismissKey = 'gifbox-explainer-dismissed';

enum PickerTab { gif, emoji }

/// Floating GIF/emoji picker anchored above [anchor] (the `CompositionMediaPicker`).
Future<void> showMediaPicker(
  BuildContext context, {
  required Rect anchor,
  required PickerTab tab,
  String? serverId,
  required void Function(String text) onText,
  required void Function(String content) onMessage,
}) {
  final store = context.read<ClientStore>();
  final settings = context.read<SettingsStore>();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close picker',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 200),
    transitionBuilder: (c, a, _, child) => FadeTransition(opacity: a, child: child),
    pageBuilder: (c, _, _) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: store),
        ChangeNotifierProvider.value(value: settings),
      ],
      child: _PickerHost(anchor: anchor, initial: tab, serverId: serverId, onText: onText, onMessage: onMessage),
    ),
  );
}

class _PickerHost extends StatefulWidget {
  const _PickerHost({required this.anchor, required this.initial, required this.serverId, required this.onText, required this.onMessage});
  final Rect anchor;
  final PickerTab initial;
  final String? serverId;
  final void Function(String) onText, onMessage;
  @override
  State<_PickerHost> createState() => _PickerHostState();
}

class _PickerHostState extends State<_PickerHost> {
  late PickerTab tab = widget.initial;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final phone = screenClassOf(size) == ScreenClass.phone;
    const w = 400.0, h = 400.0;
    final cs = context.cs;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    double left, top;
    if (phone || widget.anchor.right - w < 0 || widget.anchor.top - h - 5 < 0) {
      left = size.width - w;
      top = size.height - h - bottomInset;
    } else {
      left = widget.anchor.right - w;
      top = widget.anchor.top - h - 5;
    }
    left = left.clamp(0, (size.width - w).clamp(0, double.infinity));
    final panel = Container(
      width: phone ? size.width : w,
      height: h,
      padding: const EdgeInsets.symmetric(vertical: Gap.md),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: br(Radius_.lg),
        boxShadow: [BoxShadow(color: cs.shadow, blurRadius: 3)],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 2,
            children: [
              _Seg('GIFs', tab == PickerTab.gif, () => setState(() => tab = PickerTab.gif), start: true),
              _Seg('Emoji', tab == PickerTab.emoji, () => setState(() => tab = PickerTab.emoji), start: false),
            ],
          ),
          const SizedBox(height: Gap.md),
          Expanded(
            child: tab == PickerTab.gif
                ? _GifPicker(onMessage: (c) {
                    Navigator.pop(context);
                    widget.onMessage(c);
                  })
                : _EmojiPicker(serverId: widget.serverId, onText: widget.onText),
          ),
        ],
      ),
    );
    return Stack(
      children: [
        Positioned(left: phone ? 0 : left, top: phone ? top : top, child: Material(type: MaterialType.transparency, child: panel)),
      ],
    );
  }
}

class _Seg extends StatelessWidget {
  const _Seg(this.label, this.active, this.onTap, {required this.start});
  final String label;
  final bool active, start;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Material(
      color: active ? cs.secondaryContainer : Colors.transparent,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: cs.outline),
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(start ? 20 : 4),
          right: Radius.circular(start ? 4 : 20),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          child: Text(label, style: TextStyle(fontWeight: FontWeight.w500, color: active ? cs.onSecondaryContainer : cs.onSurface)),
        ),
      ),
    );
  }
}

// ----- emoji -----

sealed class _Item {}

class _Custom extends _Item {
  _Custom(this.emoji);
  final Json emoji;
}

class _Unicode extends _Item {
  _Unicode(this.name, this.text);
  final String name, text;
}

class _EmojiPicker extends StatefulWidget {
  const _EmojiPicker({required this.serverId, required this.onText});
  final String? serverId;
  final void Function(String) onText;
  @override
  State<_EmojiPicker> createState() => _EmojiPickerState();
}

class _EmojiPickerState extends State<_EmojiPicker> {
  final _filter = TextEditingController();
  final _scroll = ScrollController();
  final _sectionKeys = <String, GlobalKey>{};
  EmojiData? data = EmojiData.loaded;
  _Item? hovered;

  @override
  void initState() {
    super.initState();
    if (data == null) {
      EmojiData.load().then((d) {
        if (mounted) setState(() => data = d);
      });
    }
  }

  @override
  void dispose() {
    _filter.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<Json> _emojisOf(ClientStore store, String serverId) => store.emojis.values.where((e) => (e['parent'] as Map?)?['id'] == serverId).toList();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final settings = context.watch<SettingsStore>();
    final cs = context.cs;
    final d = data;
    if (d == null) return const Center(child: CircularProgressIndicator());
    final q = _filter.text.trim().toLowerCase();
    final servers = store.serverList.where((s) => _emojisOf(store, s['_id'] as String).isNotEmpty).toList();

    Widget cell(_Item it) {
      Widget child;
      String? pick;
      if (it is _Custom) {
        child = NetImage('$customEmojiBaseUrl/${it.emoji['_id']}', fit: BoxFit.contain, errorBuilder: (_, _, _) => const SizedBox.shrink());
        pick = ':${it.emoji['_id']}:';
      } else if (it is _Unicode) {
        child = EmojiView(it.text, size: 32);
        pick = it.text;
      } else {
        return const SizedBox.shrink();
      }
      return MouseRegion(
        onEnter: (_) => setState(() => hovered = it),
        child: InkWell(
          borderRadius: br(Radius_.sm),
          onTap: () => widget.onText(pick!),
          child: Padding(padding: const EdgeInsets.all(Gap.sm), child: child),
        ),
      );
    }

    final slivers = <Widget>[];
    void grid(List<_Item> items) {
      slivers.add(
        SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 40, mainAxisExtent: 40),
          delegate: SliverChildBuilderDelegate((c, i) => cell(items[i]), childCount: items.length),
        ),
      );
    }

    if (q.isNotEmpty) {
      final custom = <_Item>[
        for (final s in store.serverList)
          for (final e in _emojisOf(store, s['_id'] as String))
            if ((e['name'] as String? ?? '').toLowerCase().contains(q)) _Custom(e),
      ];
      final uni = <_Item>[
        for (final e in d.dedupe)
          if (e.shorthands.any((s) => s.toLowerCase().contains(q))) _Unicode(e.shorthands.first, e.emoji),
      ];
      grid([...custom, ...uni]);
    } else {
      for (final s in servers) {
        final id = s['_id'] as String;
        final key = _sectionKeys[id] ??= GlobalKey();
        slivers.add(
          SliverToBoxAdapter(
            child: Container(
              key: key,
              height: 40,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: Gap.md),
              child: Row(
                spacing: 8,
                children: [
                  IconAvatar(url: store.api.fileUrl('icons', s['icon'] as Map?, width: 48), name: s['name'] as String? ?? '?', size: 24, square: false),
                  Flexible(child: Text(s['name'] as String? ?? '', overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
          ),
        );
        grid([for (final e in _emojisOf(store, id)) _Custom(e)]);
      }
      slivers.add(
        SliverToBoxAdapter(
          child: Container(height: 40, alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: Gap.md), child: Text(tr('Default'))),
        ),
      );
      grid([for (final e in d.all) _Unicode(e.shorthands.first, e.emoji)]);
    }

    String? previewName;
    Widget? previewGraphic;
    String? previewFrom;
    final h = hovered;
    if (h is _Custom) {
      previewName = ':${h.emoji['name']}:';
      previewGraphic = NetImage('$customEmojiBaseUrl/${h.emoji['_id']}', width: 24, height: 24);
      previewFrom = store.servers[(h.emoji['parent'] as Map?)?['id']]?['name'] as String? ?? 'Unknown Server';
    } else if (h is _Unicode) {
      previewName = ':${h.name}:';
      previewGraphic = EmojiView(h.text, size: 24);
    }
    // keep the unused settings subscription so pack changes rebuild the grid
    settings.unicodeEmoji;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.md),
          child: TextField(
            controller: _filter,
            autofocus: screenClassOf(MediaQuery.sizeOf(context)) != ScreenClass.phone,
            decoration: InputDecoration(hintText: 'Search for emojis...', isDense: true, border: OutlineInputBorder(borderRadius: br(Radius_.xl))),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: Gap.md),
        Expanded(
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: ListView(
                  children: [
                    for (final s in servers)
                      InkWell(
                        onTap: () {
                          final ctx = _sectionKeys[s['_id']]?.currentContext;
                          if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 200));
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: IconAvatar(url: store.api.fileUrl('icons', s['icon'] as Map?, width: 64), name: s['name'] as String? ?? '?', size: 32, square: false),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    Expanded(child: CustomScrollView(controller: _scroll, slivers: slivers)),
                    SizedBox(
                      height: 40,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                        child: previewName == null
                            ? null
                            : Row(
                                spacing: 8,
                                children: [
                                  SizedBox(width: 24, height: 24, child: previewGraphic),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(previewName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                                        if (previewFrom != null)
                                          Text.rich(TextSpan(text: 'from ', children: [TextSpan(text: previewFrom, style: const TextStyle(fontWeight: FontWeight.w500))]), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant), overflow: TextOverflow.ellipsis),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ----- gifs -----

enum _Provider { gifbox, klipy }

class _GifTileData {
  _GifTileData(this.url, this.message, this.w, this.h);
  final String url;
  final String message;
  final double w, h;
}

class _GifPicker extends StatefulWidget {
  const _GifPicker({required this.onMessage});
  final void Function(String) onMessage;
  @override
  State<_GifPicker> createState() => _GifPickerState();
}

class _GifPickerState extends State<_GifPicker> {
  final _filter = TextEditingController();
  Timer? _debounce;
  String query = '';
  _Provider provider = _Provider.gifbox;
  Future<List<_GifTileData>>? _results;
  Future<List<({String title, String image, String query})>>? _categories;
  String _cacheKey = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _filter.dispose();
    super.dispose();
  }

  void _setFilter(String v) {
    _filter.text = v;
    _filter.selection = TextSelection.collapsed(offset: v.length);
    _debounce?.cancel();
    setState(() => query = v.trim().toLowerCase());
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => query = v.trim().toLowerCase());
    });
    setState(() {});
  }

  Map<String, String> get _auth {
    final t = context.read<ClientStore>().api.token;
    return {if (t != null) 'x-session-token': t};
  }

  Future<List<({String title, String image, String query})>> _loadCategories() async {
    if (provider == _Provider.gifbox) {
      final r = await http.get(Uri.parse('$gifboxUrl/categories?locale=en_US'), headers: _auth);
      if (r.statusCode >= 400) throw Exception('Gifbox categories failed: ${r.statusCode}');
      final list = jsonDecode(r.body);
      if (list is! List) return const [];
      return [for (final c in list) (title: c['title'] as String, image: c['image'] as String, query: c['title'] as String)];
    }
    final r = await http.get(Uri.parse('$klipyApiBaseUrl/${Uri.encodeComponent(_klipyKey)}/gifs/categories?locale=en_US'));
    if (r.statusCode >= 400) throw Exception('KLIPY categories failed: ${r.statusCode}');
    final cats = (jsonDecode(r.body)['data']['categories'] as List);
    return [for (final c in cats) (title: c['category'] as String, image: c['preview_url'] as String, query: c['query'] as String)];
  }

  Future<List<_GifTileData>> _loadResults() async {
    if (provider == _Provider.gifbox) {
      final path = query == 'trending' ? 'trending?locale=en_US' : 'search?locale=en_US&query=${Uri.encodeQueryComponent(query)}';
      final r = await http.get(Uri.parse('$gifboxUrl/$path'), headers: _auth);
      if (r.statusCode >= 400) throw Exception('Gifbox search failed: ${r.statusCode}');
      final results = (jsonDecode(r.body)['results'] as List?) ?? const [];
      return [
        for (final g in results)
          if (g['media_formats']?['tinywebm']?['url'] != null)
            () {
              final dims = (g['media_formats']['tinywebm']['dims'] as List?)?.cast<num>();
              return _GifTileData(g['media_formats']['tinywebm']['url'] as String, g['url'] as String, (dims?[0] ?? 4).toDouble(), (dims?[1] ?? 3).toDouble());
            }(),
      ];
    }
    final params = {'page': '1', 'per_page': '24', 'locale': 'us', 'format_filter': 'webm', 'content_filter': 'high', if (query != 'trending') 'q': query};
    final endpoint = query == 'trending' ? 'trending' : 'search';
    final r = await http.get(Uri.parse('$klipyApiBaseUrl/${Uri.encodeComponent(_klipyKey)}/gifs/$endpoint').replace(queryParameters: params));
    if (r.statusCode >= 400) throw Exception('KLIPY search failed: ${r.statusCode}');
    final body = jsonDecode(r.body);
    if (body['result'] != true) throw Exception('KLIPY search failed');
    final out = <_GifTileData>[];
    for (final g in (body['data']['data'] as List)) {
      final f = g['file'] as Map?;
      final media = f?['sm']?['webm'] ?? f?['md']?['webm'] ?? f?['hd']?['webm'];
      final url = media?['url'] as String?;
      if (url == null) continue;
      final slug = g['slug'] as String?;
      out.add(_GifTileData(url, slug != null ? '$klipyUrl/gifs/${Uri.encodeComponent(slug)}' : url, (media?['width'] as num?)?.toDouble() ?? 4, (media?['height'] as num?)?.toDouble() ?? 3));
    }
    return out;
  }

  void _shareKlipy(String slug) {
    http
        .post(
          Uri.parse('$klipyApiBaseUrl/${Uri.encodeComponent(_klipyKey)}/gifs/share/${Uri.encodeComponent(slug)}'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'q': query == 'trending' ? '' : query}),
        )
        .catchError((_) => http.Response('', 500));
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final settings = context.watch<SettingsStore>();
    final dismissed = settings.sectionState(_gifboxDismissKey, false);
    final key = '${provider.name}:$query';
    if (query.isNotEmpty && key != _cacheKey) {
      _cacheKey = key;
      _results = (provider == _Provider.klipy && _klipyKey.isEmpty) ? Future.value(const []) : _loadResults();
    }
    if (query.isEmpty && _cacheKey != 'cat:${provider.name}') {
      _cacheKey = 'cat:${provider.name}';
      _categories = (provider == _Provider.klipy && _klipyKey.isEmpty) ? Future.value(const []) : _loadCategories();
    }

    Widget tile(Widget child, VoidCallback onTap) => Material(
      color: cs.surfaceContainerHighest,
      borderRadius: br(Radius_.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: child),
    );

    Widget body;
    if (query.isEmpty) {
      if (provider == _Provider.klipy && _klipyKey.isEmpty) {
        body = const _Centered(title: 'KLIPY is not configured', body: 'Build with --dart-define=KLIPY_API_KEY=<public key> to enable KLIPY.');
      } else {
        body = FutureBuilder(
          future: _categories,
          builder: (c, snap) {
            final cats = snap.data ?? const [];
            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: Gap.md),
              children: [
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: Gap.sm,
                  crossAxisSpacing: Gap.sm,
                  childAspectRatio: 16 / 10,
                  padding: const EdgeInsets.symmetric(vertical: Gap.sm),
                  children: [
                    tile(
                      Container(
                        alignment: Alignment.bottomLeft,
                        padding: const EdgeInsets.all(Gap.md),
                        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [cs.primary, cs.tertiary])),
                        child: Text(tr('Trending GIFs'), style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                      ),
                      () => _setFilter('trending'),
                    ),
                    for (final cat in cats)
                      tile(
                        Stack(
                          fit: StackFit.expand,
                          children: [
                            NetImage(cat.image, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                            const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xB3000000)]))),
                            Padding(
                              padding: const EdgeInsets.all(Gap.md),
                              child: Align(alignment: Alignment.bottomLeft, child: Text(cat.title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500))),
                            ),
                          ],
                        ),
                        () => _setFilter(cat.query),
                      ),
                  ],
                ),
                if (provider == _Provider.klipy) const _KlipyCredit(),
              ],
            );
          },
        );
      }
    } else if (provider == _Provider.klipy && _klipyKey.isEmpty) {
      body = const _Centered(title: 'KLIPY is not configured', body: 'Build with --dart-define=KLIPY_API_KEY=<public key> to enable KLIPY.');
    } else {
      body = FutureBuilder<List<_GifTileData>>(
        future: _results,
        builder: (c, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          final gifs = snap.data ?? const [];
          if (gifs.isEmpty) {
            return provider == _Provider.klipy
                ? _Centered(title: tr('No GIFs found'), body: null, credit: true)
                : _Centered(
                    title: tr('No GIFs found'),
                    body: tr("Can't find the perfect GIF? Head to Gifbox and upload your own for everyone to use."),
                    action: FilledButton(onPressed: () => openUrl(gifboxUploadUrl), child: Text(tr('Upload to Gifbox'))),
                  );
          }
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
                sliver: SliverMasonryGrid.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: Gap.sm,
                  crossAxisSpacing: Gap.sm,
                  childCount: gifs.length,
                  itemBuilder: (c, i) {
                    final g = gifs[i];
                    return tile(
                      AspectRatio(aspectRatio: g.w / g.h, child: MediaVideo(url: g.url, controls: false, loop: true, muted: true, autoplay: true, fit: BoxFit.cover)),
                      () {
                        if (provider == _Provider.klipy) {
                          final slug = Uri.tryParse(g.message)?.pathSegments.lastOrNull;
                          if (slug != null && g.message.startsWith(klipyUrl)) _shareKlipy(slug);
                        }
                        widget.onMessage(g.message);
                      },
                    );
                  },
                ),
              ),
              SliverToBoxAdapter(
                child: provider == _Provider.klipy
                    ? const _KlipyCredit()
                    : Padding(
                        padding: const EdgeInsets.symmetric(vertical: Gap.l),
                        child: Column(
                          children: [
                            Text(tr('Got a better GIF? Share it with everyone on Gifbox.'), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                            TextButton(onPressed: () => openUrl(gifboxUploadUrl), child: Text(tr('Upload to Gifbox'))),
                          ],
                        ),
                      ),
              ),
            ],
          );
        },
      );
    }

    return Column(
      children: [
        if (provider == _Provider.gifbox && !dismissed)
          Container(
            margin: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
            padding: const EdgeInsets.all(Gap.l),
            decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: br(Radius_.md)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('GIFs are now powered by Gifbox and Klipy', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  'Gifbox is provided by StoatChat (Revolt Platforms Ltd). Klipy is provided by Kikliko Inc. Both services are free to use and allow you to upload your own GIFs for everyone to use.',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => openUrl(gifboxInfoUrl), child: Text(tr('Learn more'))),
                    FilledButton(onPressed: () => settings.setSectionState(_gifboxDismissKey, true), child: Text(tr('Got it'))),
                  ],
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.md),
          child: Row(
            spacing: 8,
            children: [
              for (final p in _Provider.values)
                Expanded(
                  child: p == provider
                      ? FilledButton(onPressed: () {}, child: Text(p == _Provider.gifbox ? 'Gifbox' : 'KLIPY'))
                      : OutlinedButton(
                          onPressed: () => setState(() {
                            provider = p;
                            _cacheKey = '';
                          }),
                          child: Text(p == _Provider.gifbox ? 'Gifbox' : 'KLIPY'),
                        ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Gap.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.md),
          child: Row(
            children: [
              if (_filter.text.isNotEmpty)
                IconButton(
                  tooltip: 'Back to categories',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => _setFilter(''),
                ),
              Expanded(
                child: TextField(
                  controller: _filter,
                  autofocus: screenClassOf(MediaQuery.sizeOf(context)) != ScreenClass.phone,
                  decoration: InputDecoration(hintText: provider == _Provider.klipy ? 'Search KLIPY' : 'Search for GIFs...', isDense: true, border: OutlineInputBorder(borderRadius: br(Radius_.xl))),
                  onChanged: _onChanged,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.md),
        Expanded(child: body),
      ],
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.title, required this.body, this.action, this.credit = false});
  final String title;
  final String? body;
  final Widget? action;
  final bool credit;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(Gap.x),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
          if (body != null) Text(body!, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: context.cs.onSurfaceVariant)),
          ?action,
          if (credit) const _KlipyCredit(),
        ],
      ),
    ),
  );
}

class _KlipyCredit extends StatelessWidget {
  const _KlipyCredit();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Gap.sm),
    child: Center(
      child: InkWell(
        onTap: () => openUrl(klipyUrl),
        child: Text('Powered by KLIPY', style: TextStyle(fontSize: 12, decoration: TextDecoration.underline, color: context.cs.onSurfaceVariant)),
      ),
    ),
  );
}
