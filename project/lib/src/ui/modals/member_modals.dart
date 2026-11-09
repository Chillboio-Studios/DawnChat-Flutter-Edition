import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../net_image.dart';
import 'package:provider/provider.dart';

import '../../api/client_store.dart';
import '../../theme/tokens.dart';
import '../widgets.dart';
import 'app_dialog.dart';
import '../../core/i18n.dart';

Widget _userHeader(String userId, String text, {List<Widget> extra = const []}) => Column(
  mainAxisSize: MainAxisSize.min,
  spacing: Gap.md,
  children: [
    UserAvatar(userId: userId, size: 64),
    Text(text, textAlign: TextAlign.center),
    ...extra,
  ],
);

String _username(ClientStore store, String id) => store.user(id)?['username'] as String? ?? 'Unknown User';

Future<void> showTimeoutMember(BuildContext context, String serverId, String userId) {
  final store = context.read<ClientStore>();
  var seconds = 60;
  const options = {60: '1 min', 300: '5 min', 600: '10 min', 3600: '1 hr', 86400: '1 day', 604800: '1 wk'};
  return showAppDialog<void>(
    context,
    title: tr('Timeout Member'),
    content: StatefulBuilder(
      builder: (c, set) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: _userHeader(userId, '${_username(store, userId)} will not be able to interact with the server until the timeout expires.')),
          const SizedBox(height: Gap.lg),
          Text(tr('Duration'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(height: Gap.s),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [for (final e in options.entries) ButtonSegment(value: e.key, label: Text(e.value, style: const TextStyle(fontSize: 12), softWrap: false))],
            selected: {seconds},
            onSelectionChanged: (v) => set(() => seconds = v.first),
          ),
        ],
      ),
    ),
    actions: [
      DlgAction(tr('Cancel')),
      DlgAction(tr('Timeout'), onPressed: () async {
        await store.api.patch('/servers/$serverId/members/$userId', {'timeout': DateTime.now().toUtc().add(Duration(seconds: seconds)).toIso8601String()});
        return null;
      }),
    ],
  );
}

Future<void> showRemoveTimeout(BuildContext context, String serverId, String userId) {
  final store = context.read<ClientStore>();
  return showAppDialog<void>(
    context,
    title: tr('Remove Timeout'),
    content: Center(child: _userHeader(userId, "${_username(store, userId)}'s timeout will be removed and they will be able to interact with the server again.")),
    actions: [
      DlgAction(tr('Cancel')),
      DlgAction(tr('Remove Timeout'), onPressed: () async {
        await store.api.patch('/servers/$serverId/members/$userId', {'remove': ['Timeout']});
        return null;
      }),
    ],
  );
}

Future<void> showKickMember(BuildContext context, String serverId, String userId) {
  final store = context.read<ClientStore>();
  return showAppDialog<void>(
    context,
    title: tr('Kick Member'),
    content: Center(child: _userHeader(userId, 'You are about to kick ${_username(store, userId)}')),
    actions: [
      DlgAction(tr('Cancel')),
      DlgAction(tr('Kick'), onPressed: () async {
        await store.api.delete('/servers/$serverId/members/$userId');
        return null;
      }),
    ],
  );
}

Future<void> showBanMember(BuildContext context, String serverId, String userId, {bool isMember = true}) {
  final store = context.read<ClientStore>();
  final reason = TextEditingController();
  var deleteSeconds = 0;
  const deletes = {0: "Don't delete messages", 3600: '1 hour', 21600: '6 hours', 86400: '1 day', 259200: '3 days', 604800: '7 days'};
  return showAppDialog<void>(
    context,
    title: isMember ? 'Ban Member' : 'Ban User',
    content: StatefulBuilder(
      builder: (c, set) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: _userHeader(
              userId,
              'You are about to ban ${_username(store, userId)}',
              extra: [if (!isMember) Text(tr('This user is not part of the server and may already be banned'))],
            ),
          ),
          const SizedBox(height: Gap.lg),
          TextField(controller: reason, maxLength: 1024, decoration: InputDecoration(labelText: tr('Reason'), hintText: tr('User broke a certain rule…'))),
          if (isMember)
            DropdownButtonFormField<int>(
              initialValue: deleteSeconds,
              decoration: InputDecoration(labelText: tr('Delete Message History')),
              items: [for (final e in deletes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => set(() => deleteSeconds = v ?? 0),
            ),
        ],
      ),
    ),
    actions: [
      DlgAction(tr('Cancel')),
      DlgAction(tr('Ban'), onPressed: () async {
        await store.api.put('/servers/$serverId/bans/$userId', {'reason': reason.text, if (isMember) 'delete_message_seconds': deleteSeconds});
        return null;
      }),
    ],
  );
}

Future<void> showRemoveGroupMember(BuildContext context, Json group, String userId) {
  final store = context.read<ClientStore>();
  return showAppDialog<void>(
    context,
    title: tr('Remove Member'),
    content: Center(child: _userHeader(userId, 'Are you sure you want to remove ${store.displayName(userId)} from ${group['name']}?')),
    actions: [
      DlgAction(tr('Cancel')),
      DlgAction(tr('Remove'), onPressed: () async {
        await store.api.delete('/channels/${group['_id']}/recipients/$userId');
        return null;
      }),
    ],
  );
}

Future<void> showDeleteChannel(BuildContext context, Json channel, {void Function()? onDone}) {
  final store = context.read<ClientStore>();
  final type = channel['channel_type'];
  final name = store.channelName(channel);
  return showAppDialog<void>(
    context,
    title: type == 'Group' ? 'Leave $name?' : type == 'DirectMessage' ? 'Close conversation with $name?' : 'Delete $name?',
    content: Text(
      type == 'Group'
          ? "You won't be able to rejoin unless you are re-invited."
          : type == 'DirectMessage'
          ? 'You can re-open it later, but it will disappear on both sides.'
          : "Once it's deleted, there's no going back.",
    ),
    actions: [
      DlgAction(tr('Cancel')),
      DlgAction(type == 'Group' ? 'Leave' : type == 'DirectMessage' ? 'Close' : 'Delete', destructive: true, onPressed: () async {
        await store.api.delete('/channels/${channel['_id']}');
        if (type == 'Group' || type == 'TextChannel' || type == 'VoiceChannel') {
          store.channels.remove(channel['_id']);
          store.refresh();
        }
        onDone?.call();
        return null;
      }),
    ],
  );
}

/// Edit nickname (and own avatar/pronouns) on a server.
Future<void> showServerIdentity(BuildContext context, String serverId, String userId) {
  final store = context.read<ClientStore>();
  final member = store.members[serverId]?[userId] ?? const <String, dynamic>{};
  final self = userId == store.userId;
  final nickname = TextEditingController(text: member['nickname'] as String? ?? '');
  final pronouns = TextEditingController(text: _pronounString(member['pronouns']));
  final initialNick = nickname.text, initialPronouns = pronouns.text;
  final hadAvatar = member['avatar'] != null;
  var removeAvatar = false;
  ({String name, List<int> bytes, String? mime})? newAvatar;

  final serverName = store.servers[serverId]?['name'] as String? ?? '';
  final display = member['nickname'] as String? ?? store.displayName(userId);

  return showAppDialog<void>(
    context,
    title: self ? 'Change identity on $serverName' : "Change $display's nickname",
    content: StatefulBuilder(
      builder: (c, set) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (self) ...[
            Row(
              spacing: Gap.lg,
              children: [
                ClipOval(
                  child: SizedBox.square(
                    dimension: 64,
                    child: newAvatar != null
                        ? Image.memory(Uint8List.fromList(newAvatar!.bytes), fit: BoxFit.cover)
                        : (hadAvatar && !removeAvatar ? NetImage(store.api.fileUrl('avatars', member['avatar'] as Map, width: 128) ?? '', fit: BoxFit.cover) : const Icon(Icons.person, size: 40)),
                  ),
                ),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.tonal(
                        onPressed: () async {
                          final r = await FilePicker.pickFiles(type: FileType.image, withData: true);
                          final f = r?.files.firstOrNull;
                          if (f?.bytes != null) set(() => newAvatar = (name: f!.name, bytes: f.bytes!, mime: null));
                        },
                        child: Text(tr('Server Avatar')),
                      ),
                      if (hadAvatar || newAvatar != null)
                        TextButton(
                          onPressed: () => set(() {
                            newAvatar = null;
                            removeAvatar = true;
                          }),
                          child: Text(tr('Remove')),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.lg),
          ],
          TextField(controller: nickname, maxLength: 32, decoration: InputDecoration(labelText: tr('Nickname'), hintText: store.user(userId)?['display_name'] as String?)),
          if (self) TextField(controller: pronouns, maxLength: 24, decoration: InputDecoration(labelText: tr('Pronouns'))),
        ],
      ),
    ),
    actions: [
      DlgAction(tr('Cancel')),
      DlgAction(tr('Save'), onPressed: () async {
        final remove = <String>[];
        final body = <String, dynamic>{};
        if (nickname.text != initialNick) {
          final n = nickname.text.trim();
          if (n.isEmpty) {
            remove.add('Nickname');
          } else {
            body['nickname'] = n;
          }
        }
        if (newAvatar != null) {
          body['avatar'] = await store.api.uploadFile('avatars', newAvatar!.name, mimeFromNameSimple(newAvatar!.name), Uint8List.fromList(newAvatar!.bytes));
        } else if (removeAvatar && hadAvatar) {
          remove.add('Avatar');
        }
        if (pronouns.text != initialPronouns) {
          if (pronouns.text.trim().isEmpty) {
            remove.add('Pronouns');
          } else {
            body['pronouns'] = pronouns.text.trim();
          }
        }
        if (remove.isNotEmpty) body['remove'] = remove;
        if (body.isNotEmpty) await store.api.patch('/servers/$serverId/members/$userId', body);
        return null;
      }),
    ],
  );
}

String _pronounString(Object? p) => p is List ? p.join('/') : (p as String? ?? '');

String mimeFromNameSimple(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    _ => 'image/jpeg',
  };
}
