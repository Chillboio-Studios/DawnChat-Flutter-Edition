import '../core/json.dart';

/// Permission bits (BigInt so bitwise ops are correct on web as well).
class Perm {
  static BigInt _b(int n) => BigInt.one << n;
  static final manageChannel = _b(0);
  static final manageServer = _b(1);
  static final managePermissions = _b(2);
  static final manageRole = _b(3);
  static final manageCustomisation = _b(4);
  static final kickMembers = _b(6);
  static final banMembers = _b(7);
  static final timeoutMembers = _b(8);
  static final assignRoles = _b(9);
  static final changeNickname = _b(10);
  static final manageNicknames = _b(11);
  static final changeAvatar = _b(12);
  static final removeAvatars = _b(13);
  static final viewChannel = _b(20);
  static final readMessageHistory = _b(21);
  static final sendMessage = _b(22);
  static final manageMessages = _b(23);
  static final manageWebhooks = _b(24);
  static final inviteOthers = _b(25);
  static final sendEmbeds = _b(26);
  static final uploadFiles = _b(27);
  static final masquerade = _b(28);
  static final react = _b(29);
  static final connect = _b(30);
  static final speak = _b(31);
  static final video = _b(32);
  static final muteMembers = _b(33);
  static final deafenMembers = _b(34);
  static final moveMembers = _b(35);
  static final listen = _b(36);
  static final mentionEveryone = _b(37);
  static final mentionRoles = _b(38);
  static final bypassSlowmode = _b(39);
  static final viewAuditLogs = _b(40);
  static final useExternalEmojis = _b(41);
  static final shareScreen = _b(42);
  static final shareCamera = _b(43);
  static final disconnectMembers = _b(44);
  static final all = (BigInt.one << 52) - BigInt.one;

  /// Default permissions of a user in a DM/group.
  static final dmDefault =
      viewChannel |
      readMessageHistory |
      sendMessage |
      sendEmbeds |
      uploadFiles |
      react |
      connect |
      speak |
      video |
      shareScreen |
      shareCamera |
      listen |
      inviteOthers;
}

BigInt _big(Object? v) => v is num ? BigInt.from(v) : BigInt.zero;

({BigInt a, BigInt d}) _ad(Object? v) {
  final m = v is Map ? v : const {};
  return (a: _big(m['a']), d: _big(m['d']));
}

/// Mirrors revolt-permissions resolution for a user in a channel.
BigInt channelPermissions({
  required Json channel,
  required Json? server,
  required Json? member,
  required String userId,
}) {
  final type = channel['channel_type'];
  switch (type) {
    case 'SavedMessages':
      return channel['user'] == userId ? Perm.all : BigInt.zero;
    case 'DirectMessage':
      return Perm.dmDefault;
    case 'Group':
      if (channel['owner'] == userId) return Perm.all;
      final recipients = (channel['recipients'] as List?) ?? const [];
      if (!recipients.contains(userId)) return BigInt.zero;
      return channel['permissions'] != null
          ? _big(channel['permissions'])
          : Perm.dmDefault;
  }
  if (server == null) return BigInt.zero;
  if (server['owner'] == userId) return Perm.all;

  var p = _big(server['default_permissions']);
  final roles = ((server['roles'] as Map?) ?? const {}).cast<String, dynamic>();
  final memberRoles = ((member?['roles'] as List?) ?? const []).cast<String>();
  final ordered = memberRoles.where(roles.containsKey).toList()
    ..sort(
      (a, b) => ((roles[b]['rank'] as num?) ?? 0).compareTo(
        (roles[a]['rank'] as num?) ?? 0,
      ),
    );

  for (final id in ordered) {
    final r = _ad(roles[id]['permissions']);
    p = (p | r.a) & ~r.d;
  }

  final def = _ad(channel['default_permissions']);
  p = (p | def.a) & ~def.d;

  final overrides = ((channel['role_permissions'] as Map?) ?? const {})
      .cast<String, dynamic>();
  for (final id in ordered) {
    if (!overrides.containsKey(id)) continue;
    final r = _ad(overrides[id]);
    p = (p | r.a) & ~r.d;
  }

  final timeout = member?['timeout'];
  if (timeout is String &&
      DateTime.tryParse(timeout)?.isAfter(DateTime.now()) == true) {
    p &= Perm.viewChannel | Perm.readMessageHistory;
  }
  return p;
}

/// Server-wide permissions (default + member roles), without channel overrides.
BigInt serverPermissions({required Json server, required Json? member}) {
  var p = _big(server['default_permissions']);
  final roles = ((server['roles'] as Map?) ?? const {}).cast<String, dynamic>();
  final mine = ((member?['roles'] as List?) ?? const []).cast<String>();
  final ordered = mine.where(roles.containsKey).toList()
    ..sort(
      (a, b) => ((roles[b]['rank'] as num?) ?? 0).compareTo(
        (roles[a]['rank'] as num?) ?? 0,
      ),
    );
  for (final id in ordered) {
    final r = _ad(roles[id]['permissions']);
    p = (p | r.a) & ~r.d;
  }
  return p;
}
