import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'clipboard_image_web.dart'
    if (dart.library.io) 'clipboard_image_io.dart'
    as clipboard;

/// Adds image paste without replacing EditableText's normal text paste action.
class ImagePasteRegion extends StatefulWidget {
  const ImagePasteRegion({
    super.key,
    required this.focusNode,
    required this.enabled,
    required this.onImage,
    this.onFiles,
    required this.onError,
    required this.builder,
  });

  final FocusNode focusNode;
  final bool enabled;
  final void Function(Uint8List bytes, String mime, String name) onImage;

  /// Called with non-image clipboard files when [onImage] finds none.
  final void Function(
    List<({String name, Uint8List bytes, String? mime})> files,
  )?
  onFiles;
  final void Function(Object error) onError;
  final Widget Function(
    BuildContext context,
    EditableTextContextMenuBuilder menuBuilder,
  )
  builder;

  @override
  State<ImagePasteRegion> createState() => _ImagePasteRegionState();
}

class _ImagePasteRegionState extends State<ImagePasteRegion> {
  late final VoidCallback _stopListening;

  @override
  void initState() {
    super.initState();
    _stopListening = clipboard.listenClipboardImages(
      enabled: () => mounted && widget.enabled && widget.focusNode.hasFocus,
      onImage: (bytes, mime, name) {
        if (mounted && widget.enabled && widget.focusNode.hasFocus) {
          widget.onImage(bytes, mime, name);
        }
      },
      onError: (error, stack) {
        if (mounted) widget.onError(error);
      },
    );
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  Future<void> _paste(VoidCallback pasteText) async {
    if (!widget.enabled) {
      pasteText();
      return;
    }
    final onImage = widget.onImage;
    try {
      final image = await clipboard.readClipboardImage();
      if (!mounted || !widget.enabled || !widget.focusNode.hasFocus) return;
      if (image != null) {
        onImage(image.bytes, image.mime, image.name);
        return;
      }
      final files = await clipboard.readClipboardFiles();
      if (!mounted || !widget.enabled || !widget.focusNode.hasFocus) return;
      if (files.isNotEmpty && widget.onFiles != null) {
        widget.onFiles!(files);
      } else {
        pasteText();
      }
    } catch (error) {
      if (mounted) widget.onError(error);
    }
  }

  Widget _menu(BuildContext context, EditableTextState editable) {
    void paste() {
      ContextMenuController.removeAny();
      _paste(() => editable.pasteText(SelectionChangedCause.toolbar));
    }

    final items = [
      for (final item in editable.contextMenuButtonItems)
        if (item.type == ContextMenuButtonType.paste)
          ContextMenuButtonItem(
            type: ContextMenuButtonType.paste,
            onPressed: paste,
          )
        else
          item,
    ];
    if (widget.enabled &&
        !items.any((item) => item.type == ContextMenuButtonType.paste)) {
      items.add(
        ContextMenuButtonItem(
          type: ContextMenuButtonType.paste,
          onPressed: paste,
        ),
      );
    }
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editable.contextMenuAnchors,
      buttonItems: items,
    );
  }

  @override
  Widget build(BuildContext context) => Actions(
    actions: {
      PasteTextIntent: _ImagePasteAction((pasteText) {
        if (clipboard.usesBrowserPasteEvents) {
          pasteText();
        } else {
          _paste(pasteText);
        }
      }),
    },
    child: widget.builder(context, _menu),
  );
}

class _ImagePasteAction extends Action<PasteTextIntent> {
  _ImagePasteAction(this.paste);
  final void Function(VoidCallback pasteText) paste;

  @override
  Object? invoke(PasteTextIntent intent) {
    final fallback = callingAction;
    paste(() => fallback?.invoke(intent));
    return null;
  }
}
