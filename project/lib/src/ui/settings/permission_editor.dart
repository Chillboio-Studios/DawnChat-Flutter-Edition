import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../widgets.dart';

enum PermissionChoice { deny, neutral, allow }

class PermissionValue {
  const PermissionValue(this.allow, this.deny);
  factory PermissionValue.from(Object? value) {
    BigInt bits(Object? raw) => BigInt.tryParse('$raw') ?? BigInt.zero;
    return value is Map
        ? PermissionValue(bits(value['a']), bits(value['d']))
        : PermissionValue(bits(value), BigInt.zero);
  }
  final BigInt allow, deny;

  PermissionChoice choice(int position) {
    final bit = BigInt.one << position;
    return allow & bit != BigInt.zero
        ? PermissionChoice.allow
        : deny & bit != BigInt.zero
        ? PermissionChoice.deny
        : PermissionChoice.neutral;
  }

  PermissionValue change(int position, PermissionChoice choice) {
    final bit = BigInt.one << position;
    return PermissionValue(
      (allow & ~bit) | (choice == PermissionChoice.allow ? bit : BigInt.zero),
      (deny & ~bit) | (choice == PermissionChoice.deny ? bit : BigInt.zero),
    );
  }

  Map<String, int> get payload => {'allow': allow.toInt(), 'deny': deny.toInt()};
  Map<String, int> get cached => {'a': allow.toInt(), 'd': deny.toInt()};
}

const permissionEntries = <(String, int)>[
  ('Manage Channel', 0), ('Manage Server', 1), ('Manage Permissions', 2),
  ('Manage Roles', 3), ('Manage Customisation', 4), ('Kick Members', 6),
  ('Ban Members', 7), ('Timeout Members', 8), ('Assign Roles', 9),
  ('Change Nickname', 10), ('Manage Nicknames', 11), ('Change Avatar', 12),
  ('Remove Avatars', 13), ('View Channel', 20), ('Read Message History', 21),
  ('Send Messages', 22), ('Manage Messages', 23), ('Manage Webhooks', 24),
  ('Invite Others', 25), ('Send Embeds', 26), ('Upload Files', 27),
  ('Masquerade', 28), ('React', 29), ('Bypass Slowmode', 39), ('Connect', 30),
  ('Speak', 31), ('Video', 32), ('Mute Members', 33), ('Deafen Members', 34),
  ('Move Members', 35), ('Listen', 36), ('Mention Everyone', 37), ('Mention Roles', 38),
];

class PermissionEditor extends StatelessWidget {
  const PermissionEditor({super.key, required this.value, required this.onChanged,
    this.overrides = true, this.server = true, this.enabled = true});
  final PermissionValue value;
  final ValueChanged<PermissionValue> onChanged;
  final bool overrides, server, enabled;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final entry in permissionEntries)
        if (server || entry.$2 == 0 || entry.$2 == 2 || entry.$2 >= 20)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: LayoutBuilder(builder: (context, constraints) {
              final control = overrides
                  ? SegmentedButton<PermissionChoice>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(value: PermissionChoice.deny, icon: const Icon(Icons.close), tooltip: tr('Deny')),
                        ButtonSegment(value: PermissionChoice.neutral, icon: const Icon(Icons.remove), tooltip: tr('Neutral')),
                        ButtonSegment(value: PermissionChoice.allow, icon: const Icon(Icons.check), tooltip: tr('Allow')),
                      ],
                      selected: {value.choice(entry.$2)},
                      onSelectionChanged: enabled ? (choice) => onChanged(value.change(entry.$2, choice.single)) : null,
                    )
                  : Switch(
                      value: value.choice(entry.$2) == PermissionChoice.allow,
                      onChanged: enabled ? (allow) => onChanged(value.change(entry.$2, allow ? PermissionChoice.allow : PermissionChoice.neutral)) : null,
                    );
              final label = Text(tr(entry.$1));
              if (constraints.maxWidth < 360 && overrides) {
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [label, control]);
              }
              return Row(children: [Expanded(child: label), control]);
            }),
          ),
    ],
  );
}

class PermissionSettings extends StatefulWidget {
  const PermissionSettings({super.key, required this.initial, required this.onSave,
    this.overrides = true, this.server = true});
  final Object? initial;
  final Future<void> Function(PermissionValue) onSave;
  final bool overrides, server;
  @override
  State<PermissionSettings> createState() => _PermissionSettingsState();
}

class _PermissionSettingsState extends State<PermissionSettings> {
  late PermissionValue value = PermissionValue.from(widget.initial);
  bool busy = false;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      PermissionEditor(value: value, overrides: widget.overrides, server: widget.server,
        enabled: !busy, onChanged: (next) => setState(() => value = next)),
      Row(children: [
        TextButton(onPressed: busy ? null : () => setState(() => value = PermissionValue.from(widget.initial)), child: Text(tr('Reset'))),
        FilledButton(onPressed: busy ? null : () async {
          setState(() => busy = true);
          try {
            await widget.onSave(value);
            if (context.mounted) showSnack(context, tr('Saved'));
          } catch (error) {
            if (context.mounted) showSnack(context, errorText(error));
          } finally {
            if (mounted) setState(() => busy = false);
          }
        }, child: Text(tr('Save permissions'))),
      ]),
    ],
  );
}