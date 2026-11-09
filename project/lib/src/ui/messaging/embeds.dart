import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../net_image.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../api/client_store.dart';
import '../../core/css_colour.dart';
import '../../core/links.dart';
import '../../state/settings_store.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../interface/discover_embed_stub.dart'
    if (dart.library.js_interop) '../interface/discover_embed_web.dart';
import '../widgets.dart';
import 'markdown_view.dart';
import '../../core/i18n.dart';


String humanFileSize(num bytes) {
  if (bytes < 1000) return '$bytes B';
  const units = ['kB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var i = -1;
  while (v >= 1000 && i < units.length - 1) {
    v /= 1000;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${units[i]}';
}

String _origin(String url) => Uri.tryParse(url)?.origin ?? '';

/// Whether an embed JSON is hosted by a known GIF provider.
bool isGif(Map embed) {
  final type = embed['type'];
  if (type == 'Website') {
    if ((embed['special'] as Map?)?['type'] == 'GIF') return true;
    final u = (embed['original_url'] ?? embed['url']) as String?;
    if (u != null) return gifProviderOrigins.contains(_origin(u));
  }
  if (type == 'Image' || type == 'Video') {
    final u = embed['url'] as String?;
    if (u != null) return gifProviderOrigins.contains(_origin(u));
  }
  return false;
}

bool isGifBox(Map embed) {
  final type = embed['type'];
  final u = (type == 'Website' ? (embed['original_url'] ?? embed['url']) : embed['url']) as String?;
  return u != null && _origin(u) == gifboxOrigin;
}

/// File/proxy URL builders bound to the instance config.
class ApiClientUrls {
  ApiClientUrls(this.autumn, this.januaryBase);
  final String autumn;
  final String januaryBase;

  factory ApiClientUrls.of(BuildContext context) {
    final c = context.read<ClientStore>().api.config;
    return ApiClientUrls(c?.autumnUrl ?? '', c?.januaryUrl ?? '');
  }

  String proxied(String url) => '$januaryBase/proxy?url=${Uri.encodeQueryComponent(url)}';
  String originalUrl(Map f) => '$autumn/${f['tag'] ?? 'attachments'}/${f['_id']}/original/${Uri.encodeComponent(f['filename'] as String? ?? '')}';
  String previewUrl(Map f) => '$autumn/${f['tag'] ?? 'attachments'}/${f['_id']}';
}

bool isSpoilerFile(Map f) => (f['filename'] as String? ?? '').startsWith('SPOILER_');

/// Automatic sizing for images, videos and embeds.
class SizedContent extends StatelessWidget {
  const SizedContent({super.key, required this.width, required this.height, required this.child});
  final double width, height;
  final Widget child;

  static (double, double) fit(double w, double h) {
    if (w <= 0 || h <= 0) {
      w = 420;
      h = 236;
    }
    if (w < 160) {
      h *= 160 / w;
      w = 160;
    }
    if (h < 120) {
      w *= 120 / h;
      h = 120;
    }
    if (w > 420) {
      h /= w / 420;
      w = 420;
    }
    if (h > 420) {
      w /= h / 420;
      h = 420;
    }
    return (w, h);
  }

  @override
  Widget build(BuildContext context) {
    final (w, h) = fit(width, height);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: double.infinity),
      child: LayoutBuilder(
        builder: (context, c) {
          final maxW = c.maxWidth.isFinite ? c.maxWidth : w;
          final ww = w > maxW ? maxW : w;
          return SizedBox(
            width: ww,
            child: AspectRatio(
              aspectRatio: w / h,
              child: ClipRRect(borderRadius: br(Radius_.md), child: child),
            ),
          );
        },
      ),
    );
  }
}

/// Spoiler cover shown over images and videos.
class SpoilerCover extends StatelessWidget {
  const SpoilerCover({super.key, required this.child, required this.spoiler});
  final Widget child;
  final bool spoiler;
  @override
  Widget build(BuildContext context) => spoiler ? _SpoilerBox(child: child) : child;
}

class _SpoilerBox extends StatefulWidget {
  const _SpoilerBox({required this.child});
  final Widget child;
  @override
  State<_SpoilerBox> createState() => _SpoilerBoxState();
}

class _SpoilerBoxState extends State<_SpoilerBox> {
  bool hidden = true;
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (hidden)
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => hidden = false),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ColorFilter.mode(Colors.black.withValues(alpha: 0.8), BlendMode.srcOver),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: cs.inverseSurface,
                          borderRadius: br(Radius_.lg),
                          boxShadow: const [BoxShadow(color: Color(0x44000000), blurRadius: 8)],
                        ),
                        child: Text(
                          tr('Click to show spoiler'),
                          style: TextStyle(color: cs.onInverseSurface, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Video backed by media_kit.
class MediaVideo extends StatefulWidget {
  const MediaVideo({
    super.key,
    required this.url,
    this.controls = true,
    this.loop = false,
    this.muted = false,
    this.autoplay = false,
    this.fit = BoxFit.contain,
  });
  final String url;
  final bool controls, loop, muted, autoplay;
  final BoxFit fit;
  @override
  State<MediaVideo> createState() => _MediaVideoState();
}

class _MediaVideoState extends State<MediaVideo> {
  late final Player _player = Player();
  late final VideoController _video = VideoController(_player);

  @override
  void initState() {
    super.initState();
    _player.setPlaylistMode(widget.loop ? PlaylistMode.single : PlaylistMode.none);
    if (widget.muted) _player.setVolume(0);
    _player.open(Media(widget.url), play: widget.autoplay);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Video(
    controller: _video,
    fit: widget.fit,
    controls: widget.controls ? AdaptiveVideoControls : NoVideoControls,
    fill: Colors.black,
  );
}

/// Audio attachment player.
class AudioPlayerBar extends StatefulWidget {
  const AudioPlayerBar({super.key, required this.url});
  final String url;
  @override
  State<AudioPlayerBar> createState() => _AudioPlayerBarState();
}

class _AudioPlayerBarState extends State<AudioPlayerBar> {
  Player? _player;
  bool playing = false;
  Duration pos = Duration.zero, dur = Duration.zero;
  final _subs = <StreamSubscription>[];

  Player get player {
    if (_player == null) {
      final p = _player = Player();
      _subs
        ..add(p.stream.playing.listen((v) => setState(() => playing = v)))
        ..add(p.stream.position.listen((v) => setState(() => pos = v)))
        ..add(p.stream.duration.listen((v) => setState(() => dur = v)));
      p.open(Media(widget.url), play: false);
    }
    return _player!;
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player?.dispose();
    super.dispose();
  }

  String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Container(
      height: 48,
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: br(Radius_.xl)),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            icon: Icon(playing ? Icons.pause : Icons.play_arrow),
            color: cs.onSurface,
            onPressed: () => player.playOrPause(),
          ),
          Text(_fmt(pos), style: TextStyle(fontSize: 12, color: cs.onSurface)),
          Expanded(
            child: Slider(
              value: dur.inMilliseconds == 0 ? 0 : pos.inMilliseconds.clamp(0, dur.inMilliseconds).toDouble(),
              max: dur.inMilliseconds == 0 ? 1 : dur.inMilliseconds.toDouble(),
              onChanged: (v) => player.seek(Duration(milliseconds: v.round())),
            ),
          ),
          Text(_fmt(dur), style: TextStyle(fontSize: 12, color: cs.onSurface)),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

/// Zoomable full-screen image / GIF viewer.
Future<void> showImageViewer(
  BuildContext context, {
  String? imageUrl,
  String? videoUrl,
  String? filename,
  String? size,
  String? downloadUrl,
  String? openUrlLink,
  double? width,
  double? height,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (c) {
      final cs = c.cs;
      final controller = TransformationController();
      void zoom(double f) {
        final m = controller.value.clone();
        final cur = m.getMaxScaleOnAxis();
        final next = (cur * f).clamp(0.1, 5.0);
        controller.value = Matrix4.identity()..scale(next);
      }

      Widget card(List<Widget> children) => Container(
        padding: const EdgeInsets.all(Gap.md),
        decoration: BoxDecoration(color: cs.surface, borderRadius: br(Radius_.lg)),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      );
      return Dialog.fullscreen(
        backgroundColor: Colors.transparent,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.pop(c),
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 120),
                  child: Center(
                    child: GestureDetector(
                      onTap: () {},
                      child: InteractiveViewer(
                        transformationController: controller,
                        minScale: 0.1,
                        maxScale: 5,
                        child: AspectRatio(
                          aspectRatio: (width != null && height != null && height > 0) ? width / height : 1,
                          child: Container(
                            color: const Color(0x99000000),
                            child: videoUrl != null
                                ? MediaVideo(url: videoUrl, loop: true, muted: true, autoplay: true, controls: false)
                                : NetImage(imageUrl!, fit: BoxFit.contain),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 16,
                left: 20,
                right: 20,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (filename != null)
                      GestureDetector(
                        onTap: () {},
                        child: Container(
                          padding: const EdgeInsets.all(Gap.md),
                          decoration: BoxDecoration(color: cs.surface, borderRadius: br(Radius_.lg)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(filename, style: TextStyle(color: cs.onSurface, fontSize: 16, fontWeight: FontWeight.w600)),
                              if (size != null) Text(size, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                            ],
                          ),
                        ),
                      )
                    else
                      const SizedBox.shrink(),
                    GestureDetector(
                      onTap: () {},
                      child: card([
                        IconButton(icon: const Icon(Icons.zoom_out), onPressed: () => zoom(0.8)),
                        IconButton(icon: const Icon(Icons.zoom_in), onPressed: () => zoom(1.25)),
                        if (downloadUrl != null)
                          IconButton(icon: const Icon(Icons.download), onPressed: () => openUrl(downloadUrl)),
                        if (openUrlLink != null)
                          IconButton(icon: const Icon(Icons.open_in_new), onPressed: () => openUrl(openUrlLink)),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(c)),
                      ]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.file, required this.url});
  final Map file;
  final String url;
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final type = (file['metadata'] as Map?)?['type'];
    final icon = switch (type) {
      'Image' => Icons.image,
      'Video' => Icons.videocam,
      'Audio' => Icons.headphones,
      'Text' => Icons.description,
      _ => Icons.insert_drive_file,
    };
    final size = (file['size'] as num?)?.toInt();
    return Row(
      children: [
        Icon(icon, size: 24, color: cs.onInverseSurface),
        const SizedBox(width: Gap.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(file['filename'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onInverseSurface)),
              if (size != null && size > 0)
                Text(humanFileSize(size), style: TextStyle(color: cs.onInverseSurface.withValues(alpha: 0.7), fontSize: 12)),
            ],
          ),
        ),
        IconButton(
          icon: Icon(Icons.download, color: cs.onInverseSurface),
          onPressed: () => openUrl(url),
          tooltip: 'Download',
        ),
      ],
    );
  }
}

class _AttachmentContainer extends StatelessWidget {
  const _AttachmentContainer({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 420),
    padding: const EdgeInsets.all(Gap.md),
    decoration: BoxDecoration(color: context.cs.inverseSurface, borderRadius: br(Radius_.md)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children),
  );
}

class _TextFile extends StatefulWidget {
  const _TextFile({required this.url, required this.size});
  final String url;
  final int? size;
  @override
  State<_TextFile> createState() => _TextFileState();
}

class _TextFileState extends State<_TextFile> {
  static const _auto = 50000;
  String? contents;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    final s = widget.size;
    if (s != null && s > 0 && s <= _auto) _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final res = await http.get(Uri.parse(widget.url));
      if (mounted) setState(() => contents = utf8.decode(res.bodyBytes, allowMalformed: true));
    } catch (_) {
      if (mounted) setState(() => contents = 'Failed to load file');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    if (contents != null) {
      return SingleChildScrollView(
        child: SelectableText(contents!, style: monoStyle(context.read<SettingsStore>(), TextStyle(color: cs.onInverseSurface, fontSize: 12))),
      );
    }
    if (loading) return const Center(child: CircularProgressIndicator());
    return Center(
      child: FilledButton(onPressed: _load, child: Text('Load file (${humanFileSize(widget.size ?? 0)})')),
    );
  }
}

/// A message attachment (Image, Video, Audio, Text, File).
class AttachmentView extends StatelessWidget {
  const AttachmentView({super.key, required this.file, this.onSecondaryTap});
  final Map file;
  final void Function(Offset position)? onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    final urls = ApiClientUrls.of(context);
    final meta = (file['metadata'] as Map?) ?? const {};
    final type = meta['type'] as String? ?? 'File';
    final original = urls.originalUrl(file);
    final spoiler = isSpoilerFile(file);
    final w = (meta['width'] as num?)?.toDouble() ?? 0;
    final h = (meta['height'] as num?)?.toDouble() ?? 0;
    final isGifFile = (file['content_type'] as String?) == 'image/gif';

    Widget wrapMenu(Widget c) => onSecondaryTap == null
        ? c
        : GestureDetector(
            onSecondaryTapUp: (d) => onSecondaryTap!(d.globalPosition),
            onLongPressStart: (d) => onSecondaryTap!(d.globalPosition),
            child: c,
          );

    switch (type) {
      case 'Image':
        final src = isGifFile ? original : urls.previewUrl(file);
        return wrapMenu(
          SizedContent(
            width: w,
            height: h,
            child: SpoilerCover(
              spoiler: spoiler,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => showImageViewer(
                    context,
                    imageUrl: original,
                    filename: file['filename'] as String?,
                    size: humanFileSize((file['size'] as num?) ?? 0),
                    downloadUrl: original,
                    width: w,
                    height: h,
                  ),
                  child: NetImage(src, fit: BoxFit.contain, errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image))),
                ),
              ),
            ),
          ),
        );
      case 'Video':
        return wrapMenu(
          SizedContent(
            width: w,
            height: h,
            child: SpoilerCover(spoiler: spoiler, child: MediaVideo(url: original)),
          ),
        );
      case 'Audio':
        return wrapMenu(
          _AttachmentContainer(
            children: [
              _InfoRow(file: file, url: original),
              const SizedBox(height: Gap.md),
              AudioPlayerBar(url: original),
            ],
          ),
        );
      case 'Text':
        return wrapMenu(
          _AttachmentContainer(
            children: [
              _InfoRow(file: file, url: original),
              const SizedBox(height: Gap.md),
              SizedBox(height: 120, child: _TextFile(url: original, size: (file['size'] as num?)?.toInt())),
            ],
          ),
        );
      default:
        return wrapMenu(_AttachmentContainer(children: [_InfoRow(file: file, url: original)]));
    }
  }
}

String? specialEmbedUrl(Map embed) {
  final s = embed['special'] as Map?;
  if (s == null) return null;
  final id = s['id'];
  final ct = (s['content_type'] as String?)?.toLowerCase();
  switch (s['type']) {
    case 'YouTube':
      final ts = s['timestamp'];
      return 'https://www.youtube-nocookie.com/embed/$id${ts != null ? '?start=$ts' : ''}';
    case 'Twitch':
      return 'https://player.twitch.tv/?$ct=$id&parent=${kIsWeb ? Uri.base.host : dawnchatHost}';
    case 'Lightspeed':
      return 'https://new.lightspeed.tv/embed/$id/stream';
    case 'Spotify':
      return 'https://open.spotify.com/embed/$ct/$id';
    case 'Soundcloud':
      return 'https://w.soundcloud.com/player/?url=${Uri.encodeQueryComponent(embed['url'] as String? ?? '')}&color=%23FF7F50&auto_play=false&hide_related=false&show_comments=true&show_user=true&show_reposts=false&show_teaser=true&visual=true';
    case 'Bandcamp':
      return 'https://bandcamp.com/EmbeddedPlayer/$ct=$id/size=large/bgcol=181a1b/linkcol=056cc4/tracklist=false/transparent=true/';
    case 'Streamable':
      return 'https://streamable.com/e/$id';
  }
  return null;
}

class SpecialEmbedView extends StatefulWidget {
  const SpecialEmbedView({super.key, required this.embed});
  final Map embed;
  @override
  State<SpecialEmbedView> createState() => _SpecialEmbedViewState();
}

class _SpecialEmbedViewState extends State<SpecialEmbedView> {
  WebViewController? _controller;

  static bool get _native =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  String? get _src => specialEmbedUrl(widget.embed);

  @override
  void initState() {
    super.initState();
    final src = _src;
    if (_native && src != null) {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..loadRequest(Uri.parse(src));
    }
  }

  (double, double) _size() {
    final video = widget.embed['video'] as Map?;
    final vw = (video?['width'] as num?)?.toDouble();
    final vh = (video?['height'] as num?)?.toDouble();
    switch ((widget.embed['special'] as Map)['type']) {
      case 'YouTube':
      case 'Bandcamp':
        return (vw ?? 1280, vh ?? 720);
      case 'Spotify':
        return (420, 355);
      case 'Soundcloud':
        return (480, 460);
      case 'Streamable':
        return (1280, 720);
      default:
        return (1280, 720);
    }
  }

  @override
  Widget build(BuildContext context) {
    final src = _src;
    if (src == null) return const SizedBox.shrink();
    final (w, h) = _size();
    Widget? inner = kIsWeb ? buildPlainIframe(src) : (_controller != null ? WebViewWidget(controller: _controller!) : null);
    inner ??= Center(
      child: FilledButton.icon(
        onPressed: () => openUrl(widget.embed['url'] as String? ?? src),
        icon: const Icon(Icons.open_in_new),
        label: const Text('Open in browser'),
      ),
    );
    return SizedContent(width: w, height: h, child: ColoredBox(color: Colors.black, child: inner));
  }
}

/// Website / Text embed card.
class TextEmbedView extends StatelessWidget {
  const TextEmbedView({super.key, required this.embed});
  final Map embed;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final urls = ApiClientUrls.of(context);
    final isWebsite = embed['type'] == 'Website';
    final colour = parseCssColour(embed['colour'] as String?) ?? cs.primary;
    final icon = embed['icon_url'] as String?;
    final title = embed['title'] as String?;
    final desc = embed['description'] as String?;
    final siteName = embed['site_name'] as String?;
    final image = embed['image'] as Map?;
    final video = embed['video'] as Map?;
    final special = (embed['special'] as Map?)?['type'] as String?;
    final media = embed['media'] as Map?;

    Widget favicon() => Padding(
      padding: const EdgeInsets.only(right: Gap.md),
      child: NetImage(
        urls.proxied(icon!),
        width: 14,
        height: 14,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );

    final children = <Widget>[
      if (isWebsite && siteName != null && siteName.isNotEmpty)
        Row(
          children: [
            if (icon != null) favicon(),
            Flexible(child: Text(siteName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cs.onPrimaryContainer))),
          ],
        ),
      if (title != null && title.isNotEmpty)
        Row(
          children: [
            if (icon != null && !isWebsite) favicon(),
            Flexible(
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: embed['url'] != null ? () => handleLink(context, embed['url'] as String) : null,
                  child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, color: cs.primary)),
                ),
              ),
            ),
          ],
        ),
      if (desc != null && desc.isNotEmpty)
        embed['type'] == 'Text'
            ? DefaultTextStyle.merge(style: const TextStyle(fontSize: 12), child: RichContent(desc))
            : Text(desc, style: TextStyle(fontSize: 12, color: cs.onPrimaryContainer)),
      if (embed['type'] == 'Text' && media != null) AttachmentView(file: media),
      if (isWebsite)
        if (special != null && special != 'None' && special != 'GIF')
          SpecialEmbedView(embed: embed)
        else if (video != null)
          SizedContent(
            width: (video['width'] as num?)?.toDouble() ?? 0,
            height: (video['height'] as num?)?.toDouble() ?? 0,
            child: MediaVideo(url: urls.proxied(video['url'] as String)),
          )
        else if (image != null && image['size'] == 'Large')
          SizedContent(
            width: (image['width'] as num?)?.toDouble() ?? 0,
            height: (image['height'] as num?)?.toDouble() ?? 0,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => showImageViewer(
                  context,
                  imageUrl: urls.proxied(image['url'] as String),
                  openUrlLink: image['url'] as String,
                  width: (image['width'] as num?)?.toDouble(),
                  height: (image['height'] as num?)?.toDouble(),
                ),
                child: NetImage(urls.proxied(image['url'] as String), fit: BoxFit.contain),
              ),
            ),
          ),
    ];

    final previewImage = isWebsite && image != null && image['size'] == 'Preview' && video == null;

    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: br(Radius_.md),
        border: Border(left: BorderSide(color: colour, width: 4)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: DefaultTextStyle.merge(
                style: TextStyle(color: cs.onPrimaryContainer),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < children.length; i++) ...[
                      if (i > 0) const SizedBox(height: Gap.md),
                      children[i],
                    ],
                  ],
                ),
              ),
            ),
            if (previewImage) ...[
              const SizedBox(width: Gap.md),
              ClipRRect(
                borderRadius: br(Radius_.md),
                child: NetImage(
                  urls.proxied(image['url'] as String),
                  width: 120,
                  height: 120,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Renders a message embed; GIF providers play as looping muted video.
class EmbedView extends StatelessWidget {
  const EmbedView({super.key, required this.embed});
  final Map embed;

  @override
  Widget build(BuildContext context) {
    final urls = ApiClientUrls.of(context);
    final gif = isGif(embed);
    final box = isGifBox(embed);
    final type = embed['type'];
    final Map? video = type == 'Video' ? embed : (gif ? embed['video'] as Map? : null);
    final Map? image = type == 'Image' ? embed : (gif ? embed['image'] as Map? : null);
    String pick(Map m) => (gif && !box ? m['url'] : urls.proxied(m['url'] as String)) as String;

    if (image != null) {
      final w = (image['width'] as num?)?.toDouble() ?? 0;
      final h = (image['height'] as num?)?.toDouble() ?? 0;
      return SizedContent(
        width: w,
        height: h,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => showImageViewer(
              context,
              imageUrl: urls.proxied(image['url'] as String),
              openUrlLink: image['url'] as String,
              width: w,
              height: h,
            ),
            child: NetImage(pick(image), fit: BoxFit.contain, errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image))),
          ),
        ),
      );
    }
    if (video != null) {
      final w = (video['width'] as num?)?.toDouble() ?? 0;
      final h = (video['height'] as num?)?.toDouble() ?? 0;
      return SizedContent(
        width: w,
        height: h,
        child: Stack(
          fit: StackFit.expand,
          children: [
            MediaVideo(url: pick(video), controls: !gif, loop: gif, muted: gif, autoplay: gif),
            if (gif)
              Positioned.fill(
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => showImageViewer(
                      context,
                      videoUrl: box ? urls.proxied(video['url'] as String) : video['url'] as String,
                      openUrlLink: video['url'] as String,
                      width: w,
                      height: h,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }
    if (type == 'Website' || type == 'Text') return TextEmbedView(embed: embed);
    return const SizedBox.shrink();
  }
}
