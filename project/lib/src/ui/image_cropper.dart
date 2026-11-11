import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../theme/tokens.dart';
import 'widgets.dart';
import '../core/i18n.dart';

typedef PickedImage = ({String name, Uint8List bytes});

/// Shape of the crop window.
enum CropShape { circle, rect }

/// Picks an image and lets the user crop it before upload.
///
/// Returns `null` when the user cancels or the file cannot be decoded.
/// The result is always a PNG named `<name>.png`.
Future<PickedImage?> pickImageForUpload(
  BuildContext context, {
  required CropShape shape,
  double aspectRatio = 1,
  String name = 'image',
}) async {
  final f = await FilePicker.pickFile(type: FileType.image);
  final bytes = f == null ? null : await f.readAsBytes();
  if (bytes == null || !context.mounted) return null;

  final decoded = decodeForCrop(bytes);
  if (!context.mounted) return null;
  if (decoded == null) {
    showSnack(context, tr('Could not read that image.'));
    return null;
  }

  return showDialog<PickedImage>(
    context: context,
    builder: (_) => ImageCropDialog(
      bytes: bytes,
      image: decoded,
      shape: shape,
      aspectRatio: aspectRatio,
      name: name,
    ),
  );
}

/// Decodes [bytes] and applies EXIF orientation. Returns null for unsupported formats.
img.Image? decodeForCrop(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    return decoded == null ? null : img.bakeOrientation(decoded);
  } catch (_) {
    return null;
  }
}

class ImageCropDialog extends StatefulWidget {
  const ImageCropDialog({
    super.key,
    required this.bytes,
    required this.image,
    required this.shape,
    required this.aspectRatio,
    required this.name,
  });

  /// Original file bytes, shown with EXIF orientation applied by the engine.
  final Uint8List bytes;

  /// Decoded, orientation-baked pixels used for the actual crop.
  final img.Image image;
  final CropShape shape;

  /// Width / height of the crop window.
  final double aspectRatio;
  final String name;

  @override
  State<ImageCropDialog> createState() => _ImageCropDialogState();
}

class _ImageCropDialogState extends State<ImageCropDialog> {
  final _tc = TransformationController();
  bool _centered = false;
  Size _viewport = Size.zero;
  Size _childSize = Size.zero;

  static const double _maxScale = 5.0;

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  double get _scale => _tc.value.getMaxScaleOnAxis();

  void _computeLayout(Size viewport) {
    _viewport = viewport;
    final imgW = widget.image.width.toDouble();
    final imgH = widget.image.height.toDouble();
    final cover = max(viewport.width / imgW, viewport.height / imgH);
    _childSize = Size(imgW * cover, imgH * cover);
    if (!_centered) {
      _centered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _resetZoom();
      });
    }
  }

  void _resetZoom() => _tc.value = Matrix4.identity()
    ..translateByDouble(
      (_viewport.width - _childSize.width) / 2,
      (_viewport.height - _childSize.height) / 2,
      0,
      1,
    );

  void _zoomBy(double factor) {
    final s = _scale;
    final target = (s * factor).clamp(1.0, _maxScale);
    if ((target - s).abs() < 1e-4) return;
    if (target <= 1.001) {
      _resetZoom();
      return;
    }
    final f = target / s;
    final cx = _viewport.width / 2, cy = _viewport.height / 2;
    final m = _tc.value.clone();
    final storage = m.storage;
    final tx = storage[12], ty = storage[13];
    // Zoom around the viewport centre: keep the child point under it fixed.
    storage[0] = target;
    storage[5] = target;
    storage[12] = cx - (cx - tx) * f;
    storage[13] = cy - (cy - ty) * f;
    _tc.value = m;
  }

  Future<void> _crop() async {
    final m = _tc.value.storage;
    final scale = m[0];
    final tx = m[12], ty = m[13];
    // Visible child rect in child coordinates.
    final x0 = (-tx) / scale, x1 = (_viewport.width - tx) / scale;
    final y0 = (-ty) / scale, y1 = (_viewport.height - ty) / scale;
    final src = widget.image;
    var ix = (x0 / _childSize.width * src.width).floor();
    var iy = (y0 / _childSize.height * src.height).floor();
    var iw = ((x1 - x0) / _childSize.width * src.width).ceil();
    var ih = ((y1 - y0) / _childSize.height * src.height).ceil();
    ix = ix.clamp(0, src.width - 1);
    iy = iy.clamp(0, src.height - 1);
    iw = iw.clamp(1, src.width - ix);
    ih = ih.clamp(1, src.height - iy);

    var cropped = img.copyCrop(src, x: ix, y: iy, width: iw, height: ih);
    const maxSide = 1024;
    final longest = max(cropped.width, cropped.height);
    if (longest > maxSide) {
      final f = maxSide / longest;
      cropped = img.copyResize(
        cropped,
        width: (cropped.width * f).round(),
        height: (cropped.height * f).round(),
      );
    }
    if (!mounted) return;
    Navigator.pop(context, (
      name: '${widget.name}.png',
      bytes: Uint8List.fromList(img.encodePng(cropped)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final size = MediaQuery.sizeOf(context);
    final pad = size.width < 560 ? 16.0 : 24.0;
    var vw = min(size.width - pad * 2, 520.0);
    var vh = vw / widget.aspectRatio;
    const maxH = 420.0;
    if (vh > maxH) {
      vh = maxH;
      vw = vh * widget.aspectRatio;
    }
    _computeLayout(Size(vw, vh));

    return Dialog(
      backgroundColor: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: br(Radius_.xl)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: vw + pad * 2,
          maxHeight: size.height - 48,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.lg, Gap.lg, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tr('Crop image'),
                      style: context.tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Gap.lg),
              child: ClipRRect(
                borderRadius: widget.shape == CropShape.circle
                    ? BorderRadius.circular(vw / 2)
                    : br(Radius_.md),
                child: SizedBox(
                  width: vw,
                  height: vh,
                  child: ColoredBox(
                    color: cs.surfaceContainerHighest,
                    child: InteractiveViewer(
                      transformationController: _tc,
                      minScale: 1.0,
                      maxScale: _maxScale,
                      boundaryMargin: EdgeInsets.zero,
                      child: SizedBox(
                        width: _childSize.width,
                        height: _childSize.height,
                        child: Image.memory(
                          widget.bytes,
                          fit: BoxFit.fill,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
              child: ValueListenableBuilder<Matrix4>(
                valueListenable: _tc,
                builder: (context, m, _) {
                  final s = m.getMaxScaleOnAxis();
                  return Row(
                    children: [
                      IconButton(
                        tooltip: tr('Zoom out'),
                        icon: const Icon(Icons.zoom_out),
                        onPressed: s > 1.01 ? () => _zoomBy(1 / 1.25) : null,
                      ),
                      Expanded(
                        child: Slider(
                          value: s.clamp(1.0, _maxScale),
                          min: 1.0,
                          max: _maxScale,
                          onChanged: (v) {
                            final cur = _scale;
                            if (cur > 0) _zoomBy(v / cur);
                          },
                        ),
                      ),
                      IconButton(
                        tooltip: tr('Zoom in'),
                        icon: const Icon(Icons.zoom_in),
                        onPressed: s < _maxScale - 0.01
                            ? () => _zoomBy(1.25)
                            : null,
                      ),
                      Text(
                        '${(s * 100).round()}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Gap.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                spacing: Gap.md,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(tr('Cancel')),
                  ),
                  FilledButton(onPressed: _crop, child: Text(tr('Crop'))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
