import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../theme/tokens.dart';
import '../widgets.dart';

/// Shared scaffold for admin pages: optional trailing action + scrolling list.
class AdminListScaffold extends StatelessWidget {
  const AdminListScaffold({
    super.key,
    required this.children,
    this.trailing,
  });
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (trailing != null)
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.all(Gap.md),
            child: trailing,
          ),
        ),
      Expanded(child: ListView(children: children)),
    ],
  );
}

/// Standard page header used across admin sections.
class AdminPageHeader extends StatelessWidget {
  const AdminPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, Gap.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tr(title),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
              for (final a in actions) ...[const SizedBox(width: Gap.sm), a],
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              tr(subtitle!),
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// Loading / error / empty state helper for admin pages.
Widget adminEmptyOrError(String? error, bool loading, String empty) {
  if (error != null) return Center(child: Text(error));
  if (loading) return const Center(child: CircularProgressIndicator());
  return Center(child: Text(tr(empty)));
}

/// Loading / error / empty state helper for admin pages.
Widget adminState({
  String? error,
  bool loading = false,
  String? empty,
}) {
  if (error != null) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gap.xl),
        child: Text(error, style: const TextStyle(color: Colors.red)),
      ),
    );
  }
  if (loading) return const Center(child: CircularProgressIndicator());
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(Gap.xl),
      child: Text(
        empty != null ? tr(empty) : tr('Nothing here yet.'),
        style: const TextStyle(color: Colors.grey),
      ),
    ),
  );
}

/// Two-state segmented control styled like the role permission editor,
/// but with only yes/no (used for admin permissions and badges).
class AdminYesNo extends StatelessWidget {
  const AdminYesNo({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => SegmentedButton<bool>(
    showSelectedIcon: false,
    segments: [
      ButtonSegment(
        value: false,
        icon: const Icon(Icons.close),
        tooltip: tr('No'),
      ),
      ButtonSegment(
        value: true,
        icon: const Icon(Icons.check),
        tooltip: tr('Yes'),
      ),
    ],
    selected: {value},
    onSelectionChanged: enabled
        ? (s) => onChanged(s.single)
        : null,
  );
}

/// One labelled row inside [AdminToggleList].
class AdminToggleRow extends StatelessWidget {
  const AdminToggleRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.description,
  });
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final control = AdminYesNo(
            value: value,
            enabled: enabled,
            onChanged: onChanged,
          );
          final labelWidget = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr(label), style: TextStyle(color: cs.onSurface)),
              if (description != null)
                Text(
                  tr(description!),
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
            ],
          );
          if (constraints.maxWidth < 360) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [labelWidget, control],
            );
          }
          return Row(
            children: [Expanded(child: labelWidget), control],
          );
        },
      ),
    );
  }
}

/// Scrollable list of yes/no toggles inside a settings-style card.
class AdminToggleList extends StatelessWidget {
  const AdminToggleList({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => CategoryGroup(children: children);
}

/// Admin permission bit definitions matching `perms` in the Rust backend.
const adminPermissionEntries = <(String, int, String)>[
  ('View Users', 1 << 0, 'View the user directory and profiles'),
  ('Edit Users', 1 << 1, 'Edit profiles, badges, avatars and identity'),
  ('Ban Users', 1 << 2, 'Ban, unban, suspend and restrict accounts'),
  ('View Reports', 1 << 3, 'View safety reports and tickets'),
  ('Manage Reports', 1 << 4, 'Resolve reports and work tickets'),
  ('View Audit', 1 << 5, 'View the platform audit log and history'),
  ('View Servers', 1 << 6, 'View the server directory'),
  ('Edit Servers', 1 << 7, 'Edit or remove server listings'),
  ('Broadcast', 1 << 8, 'Post announcements and manage changelogs'),
];

/// Editor for a user's admin permission bitfield using yes/no toggles.
/// Returns the new bitfield via [onChanged].
class AdminPermEditor extends StatelessWidget {
  const AdminPermEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });
  final int value;
  final ValueChanged<int> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => AdminToggleList(
    children: [
      for (final (label, bit, desc) in adminPermissionEntries)
        AdminToggleRow(
          label: label,
          description: desc,
          enabled: enabled,
          value: value & bit == bit,
          onChanged: (v) =>
              onChanged(v ? value | bit : value & ~bit),
        ),
    ],
  );
}

/// Known user badge bits (mirrors profile badge rendering).
const adminBadgeEntries = <(String, int)>[
  ('Developer', 1),
  ('Translator', 2),
  ('Supporter', 4),
  ('Responsible Disclosure', 8),
  ('Founder', 16),
  ('Moderation', 32),
  ('Active Supporter', 64),
  ('Paw', 128),
  ('Early Adopter', 256),
  ('Joke', 512),
];

/// Editor for a user's badge bitfield using yes/no toggles.
class AdminBadgeEditor extends StatelessWidget {
  const AdminBadgeEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });
  final int value;
  final ValueChanged<int> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => AdminToggleList(
    children: [
      for (final (label, bit) in adminBadgeEntries)
        AdminToggleRow(
          label: label,
          enabled: enabled,
          value: value & bit == bit,
          onChanged: (v) =>
              onChanged(v ? value | bit : value & ~bit),
        ),
      // Preserve unknown bits so saving never silently drops them.
      if (value & ~adminBadgeEntries.fold(0, (a, e) => a | e.$2) != 0)
        AdminToggleRow(
          label: 'Other badges (${value & ~adminBadgeEntries.fold(0, (a, e) => a | e.$2)})',
          enabled: false,
          value: true,
          onChanged: (_) {},
        ),
    ],
  );
}

/// Small helper: show a yes/no confirm dialog.
Future<bool> confirmYesNo(
  BuildContext context, {
  required String title,
  String? body,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final cs = context.cs;
  final result = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: br(Radius_.xl)),
      title: Text(tr(title)),
      content: body == null
          ? null
          : Text(tr(body), style: const TextStyle(fontSize: 14)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: Text(tr('Cancel')),
        ),
        TextButton(
          style: destructive
              ? TextButton.styleFrom(foregroundColor: cs.error)
              : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(tr(confirmLabel)),
        ),
      ],
    ),
  );
  return result ?? false;
}
