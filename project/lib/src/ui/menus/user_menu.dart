import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/client_store.dart';
import '../../api/permissions.dart';
import '../../core/links.dart';
import '../../router.dart';
import '../../state/draft_store.dart';
import '../../state/settings_store.dart';
import '../modals/member_modals.dart';
import '../modals/message_modals.dart';
import '../profile/profile.dart';
import '../widgets.dart';
import 'context_menu.dart';
import 'notification_menu.dart';
import '../../core/i18n.dart';

/// Opens the profile card (desktop) or full profile (phone) for a user.
void openUserCard(BuildContext context, String userId, {String? serverId}) =>
    showUserCard(context, userId, serverId: serverId);

Future<void> _guarded(BuildContext context, Future<void> Function() fn) async {
  try {
    await fn();
  } catch (e) {
    if (context.mounted) showSnack(context, errorText(e));
  }
}

class _VolumeSlider extends StatefulWidget {
  const _VolumeSlider({
    required this.label,
    required this.get,
    required this.set,
  });
  final String label;
  final double Function() get;
  final void Function(double) set;
  @override
  State<_VolumeSlider> createState() => _VolumeSliderState();
}

class _VolumeSliderState extends State<_VolumeSlider> {
  late double v = widget.get();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          tr(widget.label),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
        SizedBox(
          width: 220,
          child: Slider(
            max: 3,
            divisions: 30,
            value: v,
            label: '${(v * 100).round()}%',
            onChanged: (n) {
              setState(() => v = n);
              widget.set(n);
            },
          ),
        ),
      ],
    ),
  );
}

class _CheckRow extends StatefulWidget {
  const _CheckRow({required this.label, required this.get, required this.set});
  final String label;
  final bool Function() get;
  final void Function(bool) set;
  @override
  State<_CheckRow> createState() => _CheckRowState();
}

class _CheckRowState extends State<_CheckRow> {
  @override
  Widget build(BuildContext context) {
    final on = widget.get();
    return InkWell(
      onTap: () {
        widget.set(!on);
        setState(() {});
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        child: Row(
          spacing: 8,
          children: [
            Icon(Icons.mic_off, size: 16, fill: on ? 1 : 0),
            Expanded(
              child: Text(
                tr(widget.label),
                style: const TextStyle(fontSize: 14),
              ),
            ),
            Icon(
              on ? Icons.check_box : Icons.check_box_outline_blank,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

/// Context menu entries for a user (`UserContextMenu`).
List<MenuItem> userMenu(
  BuildContext context,
  String userId, {
  String? serverId,
  Json? channel,
  Json? contextMessage,
  bool inVoice = false,
  bool isScreenshare = false,
}) {
  final store = context.read<ClientStore>();
  final settings = context.read<SettingsStore>();
  final drafts = context.read<DraftStore>();
  final user = store.user(userId) ?? const <String, dynamic>{};
  final self = userId == store.userId;
  final rel = user['relationship'] as String? ?? 'None';
  final isBot = user['bot'] != null;
  final ch =
      channel ??
      (contextMessage != null
          ? store.channels[contextMessage['channel']]
          : null);
  final sid = serverId ?? ch?['server'] as String?;
  final member = sid == null ? null : store.members[sid]?[userId];
  final channelType = ch?['channel_type'];

  bool canEditIdentity() {
    if (member == null || sid == null) return false;
    return self
        ? (store.canInServer(sid, Perm.changeNickname) ||
              store.canInServer(sid, Perm.changeAvatar))
        : ((store.canInServer(sid, Perm.manageNicknames) ||
                  store.canInServer(sid, Perm.removeAvatars)) &&
              store.inferiorToMe(sid, userId));
  }

  bool canEditRoles() {
    if (member == null || sid == null) return false;
    return store.servers[sid]?['owner'] == store.userId ||
        (store.canInServer(sid, Perm.assignRoles) &&
            store.inferiorToMe(sid, userId));
  }

  bool moderate(BigInt perm) =>
      !self &&
      member != null &&
      sid != null &&
      store.canInServer(sid, perm) &&
      store.inferiorToMe(sid, userId);
  final timeoutStr = member?['timeout'] as String?;
  final inTimeout =
      timeoutStr != null &&
      (DateTime.tryParse(timeoutStr)?.isAfter(DateTime.now()) ?? false);
  final canTimeout = moderate(Perm.timeoutMembers);
  final canKick = moderate(Perm.kickMembers);
  final canBan = moderate(Perm.banMembers);
  final canBanNonMember =
      !self &&
      member == null &&
      sid != null &&
      store.canInServer(sid, Perm.banMembers);
  final canRemoveFromGroup =
      channelType == 'Group' &&
      !self &&
      ch?['owner'] != userId &&
      (ch?['owner'] == store.userId ||
          store.can(ch!['_id'] as String, Perm.manageChannel));

  Future<void> openDm() => _guarded(context, () async {
    final dm = await store.openDm(userId);
    if (context.mounted) context.goPath('/channel/${dm['_id']}');
  });

  return [
    if (inVoice && !self && !isScreenshare) ...[
      MenuItem.custom(
        _VolumeSlider(
          label: tr('Volume'),
          get: () => settings.userVolume(userId),
          set: (v) => settings.setUserVolume(userId, v),
        ),
      ),
      MenuItem.custom(
        _CheckRow(
          label: tr('Mute'),
          get: () => settings.userMuted(userId),
          set: (v) => settings.setUserMuted(userId, v),
        ),
      ),
      const MenuItem.divider(),
    ],
    if (isScreenshare && !self) ...[
      MenuItem.custom(
        _VolumeSlider(
          label: tr('Screen Share Volume'),
          get: () => settings.screenShareVolume(userId),
          set: (v) => settings.setScreenShareVolume(userId, v),
        ),
      ),
      MenuItem.custom(
        _CheckRow(
          label: tr('Mute Screen Share'),
          get: () => settings.screenShareMuted(userId),
          set: (v) => settings.setScreenShareMuted(userId, v),
        ),
      ),
      const MenuItem.divider(),
    ],
    MenuItem.button(
      tr('Profile'),
      icon: Icons.account_circle_outlined,
      onTap: () => showUserProfile(context, userId, serverId: sid),
    ),
    if (rel == 'Friend' || isBot)
      MenuItem.button(
        tr('Message'),
        icon: Icons.chat_bubble_outline,
        onTap: openDm,
      ),
    if (channelType == 'TextChannel')
      MenuItem.button(
        tr('Mention'),
        icon: Icons.alternate_email,
        onTap: () => drafts.requestInsert('<@$userId>'),
      ),
    if (channelType == 'DirectMessage') ...[
      const MenuItem.divider(),
      MenuItem.button(
        tr('Close chat'),
        icon: Icons.close,
        destructive: true,
        onTap: () =>
            showDeleteChannel(context, ch!, onDone: () => context.goPath('/')),
      ),
      ...notificationMenu(context, store, 'channel', ch!['_id'] as String),
    ],
    if (canEditIdentity() || canEditRoles()) ...[
      const MenuItem.divider(),
      if (canEditIdentity())
        MenuItem.button(
          self ? 'Edit your identity' : 'Edit identity',
          icon: Icons.face,
          onTap: () => showServerIdentity(context, sid!, userId),
        ),
      if (canEditRoles())
        MenuItem.button(
          tr('Edit roles'),
          icon: Icons.assignment_ind_outlined,
          onTap: () => showUserRoles(context, sid!, userId),
        ),
    ],
    if (!self &&
        !isBot &&
        (rel == 'None' || rel == 'Incoming' || rel == 'Outgoing')) ...[
      const MenuItem.divider(),
      if (rel == 'None')
        MenuItem.button(
          tr('Add friend'),
          icon: Icons.person_add_alt,
          onTap: () => _guarded(context, () => store.acceptFriend(userId)),
        ),
      if (rel == 'Incoming') ...[
        MenuItem.button(
          tr('Accept friend request'),
          icon: Icons.person_add_alt,
          onTap: () => _guarded(context, () => store.acceptFriend(userId)),
        ),
        MenuItem.button(
          tr('Reject friend request'),
          icon: Icons.cancel_outlined,
          destructive: true,
          onTap: () => _guarded(context, () => store.removeFriend(userId)),
        ),
      ],
      if (rel == 'Outgoing')
        MenuItem.button(
          tr('Cancel friend request'),
          icon: Icons.cancel_outlined,
          destructive: true,
          onTap: () => _guarded(context, () => store.removeFriend(userId)),
        ),
    ],
    if (canRemoveFromGroup ||
        (member != null && (canTimeout || canKick || canBan))) ...[
      const MenuItem.divider(),
      if (canRemoveFromGroup)
        MenuItem.button(
          tr('Remove Member'),
          icon: Icons.person_remove_outlined,
          destructive: true,
          onTap: () => showRemoveGroupMember(context, ch!, userId),
        ),
      if (canTimeout && !inTimeout)
        MenuItem.button(
          tr('Timeout Member'),
          icon: Icons.timer_outlined,
          destructive: true,
          onTap: () => showTimeoutMember(context, sid!, userId),
        ),
      if (canTimeout && inTimeout)
        MenuItem.button(
          tr('Remove Timeout'),
          icon: Icons.timer_off_outlined,
          destructive: true,
          onTap: () => showRemoveTimeout(context, sid!, userId),
        ),
      if (canKick)
        MenuItem.button(
          tr('Kick member'),
          icon: Icons.person_remove_outlined,
          destructive: true,
          onTap: () => showKickMember(context, sid!, userId),
        ),
      if (canBan)
        MenuItem.button(
          tr('Ban member'),
          icon: Icons.do_not_disturb_on_outlined,
          destructive: true,
          onTap: () => showBanMember(context, sid!, userId),
        ),
    ],
    if (canBanNonMember) ...[
      const MenuItem.divider(),
      MenuItem.button(
        tr('Ban user'),
        icon: Icons.do_not_disturb_on_outlined,
        destructive: true,
        onTap: () => showBanMember(context, sid, userId, isMember: false),
      ),
    ],
    if (!self) ...[
      const MenuItem.divider(),
      if (rel == 'Friend')
        MenuItem.button(
          tr('Remove friend'),
          icon: Icons.person_remove_outlined,
          destructive: true,
          onTap: () => _guarded(context, () => store.removeFriend(userId)),
        ),
      if (rel != 'Blocked')
        MenuItem.button(
          tr('Block user'),
          icon: Icons.block,
          destructive: true,
          onTap: () => _guarded(context, () => store.blockUser(userId)),
        ),
      if (rel == 'Blocked')
        MenuItem.button(
          tr('Unblock user'),
          icon: Icons.add_circle_outline,
          onTap: () => _guarded(context, () => store.unblockUser(userId)),
        ),
      if (user['privileged'] != true)
        MenuItem.button(
          tr('Report user'),
          icon: Icons.report_outlined,
          destructive: true,
          onTap: () => showReportDialog(
            context,
            type: 'User',
            id: userId,
            contextMessageId: contextMessage?['_id'] as String?,
          ),
        ),
    ],
    if (settings.adminPanel || settings.copyId) const MenuItem.divider(),
    if (settings.adminPanel)
      MenuItem.button(
        tr('Admin Panel'),
        icon: Icons.admin_panel_settings_outlined,
        onTap: () => openUrl(adminInspectUrl('user', userId)),
      ),
    if (settings.copyId)
      MenuItem.button(
        tr('Copy user ID'),
        icon: Icons.badge_outlined,
        onTap: () => copyText(context, userId),
      ),
  ];
}
