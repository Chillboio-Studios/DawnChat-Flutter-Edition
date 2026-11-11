import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../widgets.dart';
import '../../core/i18n.dart';

class DlgAction {
  const DlgAction(
    this.text, {
    this.onPressed,
    this.destructive = false,
    this.enabled = true,
  });

  /// Return false to keep the dialog open. Thrown errors are shown and keep it open.
  final Future<bool?> Function()? onPressed;
  final String text;
  final bool destructive, enabled;
}

/// Material 3 dialog matching the web client's `Dialog` (title, body, text actions).
Future<T?> showAppDialog<T>(
  BuildContext context, {
  required String title,
  Widget? content,
  List<DlgAction>? actions,
  double maxWidth = 560,
  bool scrollable = true,
  bool dismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    builder: (c) => _AppDialog(
      title: title,
      content: content,
      actions: actions ?? [DlgAction(tr('Close'))],
      maxWidth: maxWidth,
      scrollable: scrollable,
    ),
  );
}

/// Error dialog matching the web client's `Error2Modal`.
Future<void> showErrorDialog(BuildContext context, Object error) {
  return showAppDialog<void>(
    context,
    title: tr('An error occurred.'),
    content: SelectableText(
      errorText(error),
      style: const TextStyle(fontFamily: 'monospace'),
    ),
    actions: [DlgAction(tr('OK'))],
  );
}

/// "You've been signed out" notice matching the web client's `SignedOutModal`.
Future<void> showSignedOutDialog(BuildContext context) {
  return showAppDialog<void>(
    context,
    title: tr("You've been signed out of DawnChat!"),
    actions: [DlgAction(tr('OK'))],
  );
}

class _AppDialog extends StatefulWidget {
  const _AppDialog({
    required this.title,
    required this.content,
    required this.actions,
    required this.maxWidth,
    required this.scrollable,
  });
  final String title;
  final Widget? content;
  final List<DlgAction> actions;
  final double maxWidth;
  final bool scrollable;
  @override
  State<_AppDialog> createState() => _AppDialogState();
}

class _AppDialogState extends State<_AppDialog> {
  bool busy = false;

  Future<void> _run(DlgAction a) async {
    if (a.onPressed == null) {
      Navigator.pop(context);
      return;
    }
    setState(() => busy = true);
    try {
      final keep = await a.onPressed!();
      if (!mounted) return;
      if (keep == false) {
        setState(() => busy = false);
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => busy = false);
      showSnack(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final body = widget.content == null
        ? null
        : (widget.scrollable
              ? SingleChildScrollView(child: widget.content)
              : widget.content);
    return AlertDialog(
      backgroundColor: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: br(Radius_.xl)),
      title: Text(tr(widget.title)),
      titleTextStyle: Theme.of(context).textTheme.headlineSmall
          ?.copyWith(color: cs.onSurface),
      content: body == null
          ? null
          : ConstrainedBox(
              constraints: BoxConstraints(maxWidth: widget.maxWidth),
              child: body,
            ),
      actions: [
        for (final a in widget.actions)
          TextButton(
            style: a.destructive
                ? TextButton.styleFrom(foregroundColor: cs.error)
                : null,
            onPressed: busy || !a.enabled ? null : () => _run(a),
            child: Text(tr(a.text)),
          ),
      ],
    );
  }
}
