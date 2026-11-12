import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/image_cache.dart';

typedef NetImageError = Widget Function(
  BuildContext context,
  Object error,
  StackTrace? stack,
);

/// Network image with a persistent disk cache and parallel downloads.
class NetImage extends StatelessWidget {
  const NetImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit,
    this.errorBuilder,
  });
  final String url;
  final double? width, height;
  final BoxFit? fit;
  final NetImageError? errorBuilder;

  @override
  Widget build(BuildContext context) {
    // Blank URLs have no image — same guard as the Android RemoteImage fix.
    if (url.isEmpty) {
      return errorBuilder?.call(context, '', null) ??
          SizedBox(width: width, height: height);
    }
    if (!useDiskImageCache) {
      return Image.network(
        url,
        width: width,
        height: height,
        fit: fit,
        cacheWidth: width != null && width!.isFinite
            ? (width! * MediaQuery.devicePixelRatioOf(context)).ceil()
            : null,
        cacheHeight: height != null && height!.isFinite
            ? (height! * MediaQuery.devicePixelRatioOf(context)).ceil()
            : null,
        filterQuality: FilterQuality.medium,
        errorBuilder: errorBuilder,
      );
    }
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final w = width != null && width!.isFinite ? width : null;
    final h = height != null && height!.isFinite ? height : null;
    final scale = dpr < 2.0 ? 2.0 : dpr;
    final targetW = w == null ? null : (w * scale).ceil();
    final targetH = h == null ? null : (h * scale).ceil();
    return CachedNetworkImage(
      imageUrl: url,
      cacheManager: imageCacheManager,
      width: width,
      height: height,
      fit: fit,
      filterQuality: FilterQuality.medium,
      memCacheWidth: targetW != null && targetW < 256 ? 256 : targetW,
      memCacheHeight: targetH != null && targetH < 256 ? 256 : targetH,
      fadeInDuration: const Duration(milliseconds: 100),
      fadeOutDuration: Duration.zero,
      errorWidget: (c, u, e) =>
          errorBuilder?.call(c, e, null) ?? const SizedBox.shrink(),
    );
  }
}

ImageProvider netImageProvider(String url) => url.isEmpty
    ? MemoryImage(Uint8List(0))
    : !useDiskImageCache
    ? NetworkImage(url)
    : CachedNetworkImageProvider(url, cacheManager: imageCacheManager);

/// Network SVG backed by the same cache.
class NetSvg extends StatelessWidget {
  const NetSvg(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.placeholderBuilder,
    this.errorBuilder,
  });
  final String url;
  final double? width, height;
  final WidgetBuilder? placeholderBuilder;
  final NetImageError? errorBuilder;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return errorBuilder?.call(context, 'Empty URL', null) ??
          const SizedBox.shrink();
    }
    if (!useDiskImageCache) {
      return SvgPicture.network(
        url,
        width: width,
        height: height,
        placeholderBuilder: placeholderBuilder,
        errorBuilder: errorBuilder,
      );
    }
    return FutureBuilder(
      future: cachedBytes(url),
      builder: (c, snap) {
        if (snap.hasData) {
          return SvgPicture.memory(
            snap.data!,
            width: width,
            height: height,
            errorBuilder: errorBuilder,
          );
        }
        if (snap.hasError)
          return errorBuilder?.call(c, snap.error!, snap.stackTrace) ??
              const SizedBox.shrink();
        return placeholderBuilder?.call(c) ??
            SizedBox(width: width, height: height);
      },
    );
  }
}
