import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/client_store.dart';
import '../../api/permissions.dart';
import '../../core/css_colour.dart';
import '../../core/i18n.dart';
import '../modals/member_modals.dart';
import '../widgets.dart';
import 'permission_editor.dart';

class RoleEditor extends StatefulWidget {
  const RoleEditor({super.key, required this.serverId, required this.roleId, required this.onBack});
  final String serverId, roleId;
  final VoidCallback onBack;
  @override
  State<RoleEditor> createState() => _RoleEditorState();
}

class _RoleEditorState extends State<RoleEditor> {
  late final store = context.read<ClientStore>();
  Map<String, dynamic> get role =>
      (((store.servers[widget.serverId]?['roles'] as Map?)?[widget.roleId] as Map?) ?? {}).cast<String, dynamic>();
  late final name = TextEditingController(text: role['name'] as String? ?? '');
  late final colour = TextEditingController(text: role['colour'] as String? ?? '');
  late bool hoist = role['hoist'] == true;
  late PermissionValue permissions = PermissionValue.from(role['permissions']);
  PlatformFile? icon;
  bool removeIcon = false, busy = false;

  @override
  void dispose() {
    name.dispose();
    colour.dispose();
    super.dispose();
  }

  void reset() => setState(() {
    name.text = role['name'] as String? ?? '';
    colour.text = role['colour'] as String? ?? '';
    hoist = role['hoist'] == true;
    permissions = PermissionValue.from(role['permissions']);
    icon = null;
    removeIcon = false;
  });

  Future<void> save() async {
    if (name.text.trim().isEmpty) return;
    if (colour.text.isNotEmpty && parseCssColour(colour.text) == null) {
      showSnack(context, tr('Invalid colour'));
      return;
    }
    setState(() => busy = true);
    try {
      final path = '/servers/${widget.serverId}';
      final canEdit = store.canInServer(widget.serverId, Perm.manageRole);
      if (canEdit) {
        final remove = <String>[];
        final body = <String, dynamic>{'name': name.text.trim(), 'hoist': hoist};
        if (colour.text.trim().isEmpty) {
          remove.add('Colour');
        } else {
          body['colour'] = colour.text.trim();
        }
        if (icon?.bytes != null) {
          body['icon'] = await store.api.uploadFile('icons', icon!.name, mimeFromNameSimple(icon!.name), icon!.bytes!);
        } else if (removeIcon) {
          remove.add('Icon');
        }
        if (remove.isNotEmpty) body['remove'] = remove;
        final response = await store.api.patch('$path/roles/${widget.roleId}', body);
        role.addAll({'name': name.text.trim(), 'hoist': hoist});
        role['colour'] = colour.text.trim().isEmpty ? null : colour.text.trim();
        if (removeIcon) role.remove('icon');
        if (response is Map) role.addAll(response.cast<String, dynamic>());
      }
      if (store.canInServer(widget.serverId, Perm.managePermissions)) {
        await store.api.put('$path/permissions/${widget.roleId}', {'permissions': permissions.payload});
        role['permissions'] = permissions.cached;
      }
      store.refresh();
      if (mounted) showSnack(context, tr('Saved'));
    } catch (error) {
      if (mounted) showSnack(context, errorText(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = store.canInServer(widget.serverId, Perm.manageRole) && !busy;
    final canPermissions = store.canInServer(widget.serverId, Perm.managePermissions) && !busy;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [
      TextButton.icon(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back), label: Text(tr('Roles'))),
      TextField(controller: name, enabled: canEdit, maxLength: 32, decoration: InputDecoration(labelText: tr('Role Name'))),
      Row(children: [
        Container(width: 28, height: 28, decoration: BoxDecoration(color: parseCssColour(colour.text) ?? Theme.of(context).colorScheme.outline, shape: BoxShape.circle)),
        const SizedBox(width: 12),
        Expanded(child: TextField(controller: colour, enabled: canEdit, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: tr('Role Colour')))),
        IconButton(tooltip: tr('Reset'), onPressed: canEdit ? () => setState(() => colour.clear()) : null, icon: const Icon(Icons.restart_alt)),
      ]),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.tonalIcon(onPressed: canEdit ? () async {
          final result = await FilePicker.pickFiles(type: FileType.image, withData: true);
          if (mounted && result?.files.firstOrNull != null) setState(() { icon = result!.files.first; removeIcon = false; });
        } : null, icon: const Icon(Icons.upload), label: Text(icon?.name ?? tr('Role Icon'))),
        if (role['icon'] != null || icon != null)
          IconButton(tooltip: tr('Remove'), onPressed: canEdit ? () => setState(() { icon = null; removeIcon = true; }) : null, icon: const Icon(Icons.delete_outline)),
      ]),
      Material(color: Colors.transparent, child: SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(tr('Hoist Role')), subtitle: Text(tr('Display users with this role separately in the member list')), value: hoist, onChanged: canEdit ? (next) => setState(() => hoist = next) : null)),
      const Divider(),
      PermissionEditor(value: permissions, enabled: canPermissions, onChanged: (next) => setState(() => permissions = next)),
      Wrap(spacing: 8, children: [
        TextButton(onPressed: busy ? null : reset, child: Text(tr('Reset'))),
        FilledButton(onPressed: canEdit || canPermissions ? save : null, child: Text(tr('Save'))),
        IconButton(tooltip: tr('Copy role ID'), onPressed: () => copyText(context, widget.roleId), icon: const Icon(Icons.copy)),
        IconButton(tooltip: tr('Delete Role'), icon: const Icon(Icons.delete_outline), onPressed: canEdit ? () async {
          if (!await confirm(context, tr('Delete Role'), name.text, action: tr('Delete'))) return;
          try {
            await store.api.delete('/servers/${widget.serverId}/roles/${widget.roleId}');
            (store.servers[widget.serverId]!['roles'] as Map).remove(widget.roleId);
            store.refresh();
            widget.onBack();
          } catch (error) {
            if (context.mounted) showSnack(context, errorText(error));
          }
        } : null),
      ]),
    ]);
  }
}