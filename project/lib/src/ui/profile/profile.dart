import 'package:flutter/material.dart';
import '../net_image.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../api/client_store.dart';
import '../../api/permissions.dart';
import '../../core/css_colour.dart';
import '../../router.dart';
import '../../state/settings_store.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../menus/context_menu.dart';
import '../menus/user_menu.dart';
import '../messaging/embeds.dart';
import '../messaging/markdown_view.dart';
import '../messaging/time_utils.dart';
import '../modals/app_dialog.dart';
import '../modals/member_modals.dart';
import '../settings/settings_page.dart';
import '../widgets.dart';

// stoat.js UserBadges bit flags
const _badgeDeveloper = 1,
    _badgeTranslator = 2,
    _badgeSupporter = 4,
    _badgeResponsibleDisclosure = 8,
    _badgeFounder = 16,
    _badgeModeration = 32,
    _badgePaw = 128,
    _badgeEarlyAdopter = 256,
    _badgeJoke1 = 512;

/// Loads profile, mutuals and bot info for a user.
class ProfileData extends ChangeNotifier {
  ProfileData(this.store, this.userId) {
    _load();
  }
  final ClientStore store;
  final String userId;
  Json? profile;
  List<String> mutualUsers = const [];
  List<Json> mutualGroups = const [];
  Json? publicBot;
  bool _disposed = false;

  Json get user => store.user(userId) ?? const {};

  Future<void> _load() async {
    if (store.users[userId] == null) {
      try {
        await store.fetchUser(userId);
      } catch (_) {}
    }
    try {
      profile = ((await store.api.get('/users/$userId/profile')) as Map).cast<String, dynamic>();
    } catch (_) {}
    _notify();
    if (userId != store.userId && user['bot'] == null) {
      try {
        final r = (await store.api.get('/users/$userId/mutual')) as Map;
        mutualUsers = ((r['users'] as List?) ?? const []).cast<String>().where(store.users.containsKey).toList();
        mutualGroups = [
          for (final s in ((r['servers'] as List?) ?? const []).cast<String>())
            if (store.servers[s] != null) {...store.servers[s]!, '_kind': 'server'},
          for (final c in store.channels.values)
            if (c['channel_type'] == 'Group' && ((c['recipients'] as List?) ?? const []).contains(userId)) {...c, '_kind': 'group'},
        ];
      } catch (_) {}
    }
    if (user['bot'] != null) {
      try {
        publicBot = ((await store.api.get('/bots/$userId/invite')) as Map).cast<String, dynamic>();
      } catch (_) {}
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// A card in the profile grid: [span] columns wide; [aspect] fixes width/height.
class ProfileCell {
  ProfileCell({required this.span, required this.child, this.aspect});
  final int span;
  final double? aspect;
  final Widget child;
}

class ProfileGrid extends StatelessWidget {
  const ProfileGrid({super.key, required this.cols, required this.cells});
  final int cols;
  final List<ProfileCell> cells;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(Gap.md),
    child: LayoutBuilder(
      builder: (c, box) {
        const gap = Gap.md;
        final cw = (box.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final cell in cells)
              SizedBox(
                width: cw * cell.span + gap * (cell.span - 1),
                height: cell.aspect == null ? null : (cw * cell.span + gap * (cell.span - 1)) / cell.aspect!,
                child: cell.child,
              ),
          ],
        );
      },
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child, this.onTap, this.clip = true});
  final String title;
  final Widget child;
  final VoidCallback? onTap;
  final bool clip;
  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: br(Radius_.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Gap.sm,
            children: [
              Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: cs.onSurface)),
              if (clip) Expanded(child: ClipRect(child: child)) else child,
            ],
          ),
        ),
      ),
    );
  }
}

// ----- sections -----

class ProfileBanner extends StatefulWidget {
  const ProfileBanner({super.key, required this.data, this.serverId, this.onTap, this.onTapAvatar});
  final ProfileData data;
  final String? serverId;
  final VoidCallback? onTap, onTapAvatar;
  @override
  State<ProfileBanner> createState() => _ProfileBannerState();
}

class _ProfileBannerState extends State<ProfileBanner> {
  bool copied = false;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final u = widget.data.user;
    final sid = widget.serverId;
    final member = sid == null ? null : store.members[sid]?[widget.data.userId];
    final bg = store.api.fileUrl('backgrounds', widget.data.profile?['background'] as Map?, width: 800);
    final display = member?['nickname'] as String? ?? u['display_name'] as String? ?? u['username'] as String?;
    final username = u['username'] as String? ?? '';
    final pr = member?['pronouns'] ?? u['pronouns'];
    final pronouns = pr is List ? pr.join('/') : pr as String?;
    final avatarUrl = store.avatarUrl(widget.data.userId, size: 96);

    return Material(
      borderRadius: br(Radius_.xl),
      clipBehavior: Clip.antiAlias,
      color: context.cs.primaryContainer,
      child: InkWell(
        onTap: widget.onTap,
        child: Container(
          height: 120,
          padding: const EdgeInsets.all(Gap.lg),
          decoration: BoxDecoration(
            image: bg == null ? null : DecorationImage(image: netImageProvider(bg), fit: BoxFit.cover),
          ),
          foregroundDecoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x33000000), Color(0xB3000000)]),
          ),
          alignment: Alignment.bottomLeft,
          child: DefaultTextStyle.merge(
            style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.15),
            child: Row(
              spacing: Gap.lg,
              children: [
                GestureDetector(
                  onTap: widget.onTapAvatar,
                  child: UserAvatar(userId: widget.data.userId, size: 48, showStatus: true, url: avatarUrl),
                ),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (display != username) Text(display ?? '', style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                      Row(
                        children: [
                          Tooltip(
                            message: copied ? 'Copied!' : 'Click to copy username',
                            child: GestureDetector(
                              onTap: () async {
                                await Clipboard.setData(ClipboardData(text: '$username#${u['discriminator']}'));
                                setState(() => copied = true);
                                Future.delayed(const Duration(seconds: 2), () {
                                  if (mounted) setState(() => copied = false);
                                });
                              },
                              child: Text.rich(TextSpan(text: username, children: [TextSpan(text: '#${u['discriminator']}', style: const TextStyle(fontWeight: FontWeight.w200))])),
                            ),
                          ),
                          if (pronouns != null && pronouns.isNotEmpty)
                            Expanded(child: Text(pronouns, textAlign: TextAlign.right, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w200))),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ProfileActions extends StatelessWidget {
  const ProfileActions({super.key, required this.data, this.serverId, required this.onClose});
  final ProfileData data;
  final String? serverId;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final id = data.userId;
    final rel = data.user['relationship'] as String? ?? 'None';
    final isBot = data.user['bot'] != null;
    final self = id == store.userId;
    final sid = serverId != null && store.members[serverId]?[id] != null ? serverId : null;

    Future<void> run(Future<void> Function() fn) async {
      try {
        await fn();
      } catch (e) {
        if (context.mounted) showSnack(context, errorText(e));
      }
    }

    bool canEdit() {
      if (sid != null) {
        return self
            ? (store.canInServer(sid, Perm.changeNickname) || store.canInServer(sid, Perm.changeAvatar))
            : ((store.canInServer(sid, Perm.manageNicknames) || store.canInServer(sid, Perm.removeAvatars)) && store.inferiorToMe(sid, id));
      }
      return self;
    }

    final cs = context.cs;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      spacing: Gap.md,
      children: [
        if (rel == 'None' && !isBot) FilledButton.tonal(onPressed: () => run(() => store.acceptFriend(id)), child: const Text('Add Friend')),
        if (rel == 'Incoming') ...[
          FilledButton.tonal(onPressed: () => run(() => store.acceptFriend(id)), child: const Text('Accept friend request')),
          IconButton(onPressed: () => run(() => store.removeFriend(id)), icon: const Icon(Icons.cancel)),
        ],
        if (rel == 'Outgoing') FilledButton.tonal(onPressed: () => run(() => store.removeFriend(id)), child: const Text('Cancel friend request')),
        if (rel == 'Friend')
          FilledButton.tonal(
            onPressed: () => run(() async {
              final dm = await store.openDm(id);
              onClose();
              if (context.mounted) context.goPath('/channel/${dm['_id']}');
            }),
            child: const Text('Message'),
          ),
        if (data.publicBot != null) FilledButton.tonal(onPressed: () => showAddBot(context, data.publicBot!), child: const Text('Add Bot')),
        if (canEdit())
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit, size: 16),
            onPressed: () {
              if (sid != null) {
                showServerIdentity(context, sid, id);
              } else {
                onClose();
                showSettings(context, page: 'profile');
              }
            },
          ),
        Builder(
          builder: (c) => IconButton(
            icon: Icon(Icons.more_vert, color: cs.onSurface),
            onPressed: () {
              final box = c.findRenderObject() as RenderBox;
              final p = box.localToGlobal(Offset(0, box.size.height));
              showContextMenu(context, p, userMenu(context, id, serverId: sid));
            },
          ),
        ),
      ],
    );
  }
}

ProfileCell? _roles(BuildContext context, ProfileData d, String? sid) {
  final store = context.read<ClientStore>();
  if (sid == null || store.members[sid]?[d.userId] == null) return null;
  final roles = store.memberRoles(sid, d.userId);
  if (roles.isEmpty) return null;
  final cs = context.cs;
  return ProfileCell(
    span: 1,
    aspect: 1,
    child: _Card(
      title: 'Roles',
      onTap: () => showUserRoles(context, sid, d.userId),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          for (final r in roles.reversed)
            Row(
              spacing: 8,
              children: [
                Expanded(child: Text(r['name'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
                Container(width: 8, height: 8, decoration: BoxDecoration(color: parseCssColour(r['colour'] as String?) ?? cs.outlineVariant, shape: BoxShape.circle)),
              ],
            ),
        ],
      ),
    ),
  );
}

ProfileCell? _status(BuildContext context, ProfileData d) {
  final text = (d.user['status'] as Map?)?['text'] as String?;
  if (text == null || text.isEmpty) return null;
  return ProfileCell(span: 1, aspect: 1, child: _Card(title: 'Status', child: SingleChildScrollView(child: SelectableText(text, style: const TextStyle(fontSize: 14)))));
}

ProfileCell? _badges(BuildContext context, ProfileData d) {
  final bits = (d.user['badges'] as num?)?.toInt() ?? 0;
  final raccoon = d.userId == '01EX2NCWQ0CHS3QJF0FEQS1GR4';
  if (bits == 0 && !raccoon) return null;
  final cs = context.cs;
  Widget b(String asset, String tip) => Tooltip(message: tip, child: SizedBox(width: 24, height: 24, child: BadgeIcon(name: asset, size: 24)));
  return ProfileCell(
    span: 1,
    aspect: 1,
    child: _Card(
      title: 'Badges',
      child: SingleChildScrollView(
        child: Wrap(
          spacing: Gap.md,
          runSpacing: Gap.md,
          children: [
            if (bits & _badgeFounder != 0) b('founder', 'DawnChat Founder'),
            if (bits & _badgeDeveloper != 0) b('developer', 'DawnChat Developer'),
            if (bits & _badgeSupporter != 0) b('supporter', 'Donated to DawnChat'),
            if (bits & _badgeTranslator != 0) b('translator', 'Helped translate DawnChat'),
            if (bits & _badgeEarlyAdopter != 0) b('early_adopter', 'One of the first 1000 users!'),
            if (bits & _badgeModeration != 0) b('moderation', 'Platform Moderator'),
            if (bits & _badgeResponsibleDisclosure != 0) Tooltip(message: 'Responsibly disclosed security issues', child: Icon(Icons.shield, size: 24, color: cs.onSurface)),
            if (bits & _badgeJoke1 != 0) ...[b('amog', 'irrelevant joke badge 1'), b('amorbus', 'irrelevant joke badge 2')],
            if (bits & _badgePaw != 0) b('paw', '🦊'),
            if (raccoon) b('raccoon', '🦝'),
          ],
        ),
      ),
    ),
  );
}

ProfileCell _joined(BuildContext context, ProfileData d, String? sid) {
  final store = context.read<ClientStore>();
  final settings = context.read<SettingsStore>();
  final member = sid == null ? null : store.members[sid]?[d.userId];
  final created = ulidTime(d.userId);
  final joined = member?['joined_at'] != null ? DateTime.tryParse(member!['joined_at'] as String) : null;
  final cs = context.cs;
  Widget label(String t) => Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: cs.onSurface));
  return ProfileCell(
    span: 1,
    aspect: 1,
    child: _Card(
      title: 'Joined',
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            label('DawnChat'),
            Text(formatJoined(settings, created), style: const TextStyle(fontSize: 14)),
            if (joined != null) ...[
              label(store.servers[sid]?['name'] as String? ?? ''),
              Text(formatJoined(settings, joined), style: const TextStyle(fontSize: 14)),
            ],
          ],
        ),
      ),
    ),
  );
}

ProfileCell? _owner(BuildContext context, ProfileData d) {
  final owner = (d.user['bot'] as Map?)?['owner'] as String?;
  if (owner == null) return null;
  return ProfileCell(
    span: 1,
    aspect: 1,
    child: _OwnerCard(ownerId: owner),
  );
}

class _OwnerCard extends StatefulWidget {
  const _OwnerCard({required this.ownerId});
  final String ownerId;
  @override
  State<_OwnerCard> createState() => _OwnerCardState();
}

class _OwnerCardState extends State<_OwnerCard> {
  @override
  void initState() {
    super.initState();
    final store = context.read<ClientStore>();
    if (store.users[widget.ownerId] == null) store.fetchUser(widget.ownerId).catchError((_) => <String, dynamic>{});
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final u = store.user(widget.ownerId);
    return _Card(
      title: 'Owner',
      onTap: () => showUserProfile(context, widget.ownerId),
      child: Row(
        spacing: 8,
        children: [
          UserAvatar(userId: widget.ownerId, size: 20),
          Expanded(child: Text(u == null ? '' : (u['display_name'] as String? ?? '${u['username']}#${u['discriminator']}'), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

List<ProfileCell> _mutuals(BuildContext context, ProfileData d, String? sid) {
  final store = context.read<ClientStore>();
  return [
    if (d.mutualUsers.isNotEmpty)
      ProfileCell(
        span: 1,
        aspect: 1,
        child: _Card(
          title: 'Mutuals',
          onTap: () => showMutualFriends(context, d.mutualUsers, serverId: sid),
          child: SingleChildScrollView(child: Wrap(spacing: Gap.md, runSpacing: Gap.md, children: [for (final u in d.mutualUsers) UserAvatar(userId: u, size: 20)])),
        ),
      ),
    if (d.mutualGroups.isNotEmpty)
      ProfileCell(
        span: 1,
        aspect: 1,
        child: _Card(
          title: 'Groups',
          onTap: () => showMutualGroups(context, d.mutualGroups),
          child: SingleChildScrollView(
            child: Wrap(
              spacing: Gap.md,
              runSpacing: Gap.md,
              children: [
                for (final g in d.mutualGroups)
                  IconAvatar(url: store.api.fileUrl('icons', g['icon'] as Map?, width: 40), name: g['name'] as String? ?? '?', size: 20, square: g['_kind'] != 'server'),
              ],
            ),
          ),
        ),
      ),
  ];
}

ProfileCell? _bio(BuildContext context, ProfileData d, {required bool full, VoidCallback? onTap, required int cols}) {
  final content = d.profile?['content'] as String?;
  if (content == null || content.isEmpty) return null;
  return ProfileCell(
    span: full ? cols : 2,
    aspect: full ? null : 2,
    child: Builder(
      builder: (c) {
        final inner = Padding(
          padding: EdgeInsets.zero,
          child: SelectionArea(child: RichContent(content)),
        );
        return Material(
          color: c.cs.surfaceContainerLow,
          borderRadius: br(Radius_.lg),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(Gap.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: full ? MainAxisSize.min : MainAxisSize.max,
                spacing: Gap.sm,
                children: [
                  Text('Bio', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: c.cs.onSurface)),
                  if (full) inner else Expanded(child: ClipRect(child: inner)),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

// ----- entry points -----

Future<void> showUserProfile(BuildContext context, String userId, {String? serverId}) {
  final store = context.read<ClientStore>();
  final settings = context.read<SettingsStore>();
  return showDialog<void>(
    context: context,
    builder: (c) => MultiProvider(
      providers: [ChangeNotifierProvider.value(value: store), ChangeNotifierProvider.value(value: settings)],
      child: _ProfileModal(userId: userId, serverId: serverId, parent: context),
    ),
  );
}

class _ProfileModal extends StatefulWidget {
  const _ProfileModal({required this.userId, required this.serverId, required this.parent});
  final String userId;
  final String? serverId;
  final BuildContext parent;
  @override
  State<_ProfileModal> createState() => _ProfileModalState();
}

class _ProfileModalState extends State<_ProfileModal> {
  late final ProfileData data = ProfileData(context.read<ClientStore>(), widget.userId);

  @override
  void dispose() {
    data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    return ListenableBuilder(
      listenable: data,
      builder: (c, _) {
        final u = data.user;
        final bgFile = data.profile?['background'] as Map?;
        final avatarFile = u['avatar'] as Map?;
        final urls = ApiClientUrls.of(c);
        final cells = <ProfileCell>[
          ProfileCell(
            span: 3,
            child: ProfileBanner(
              data: data,
              serverId: widget.serverId,
              onTap: bgFile == null ? null : () => showImageViewer(c, imageUrl: urls.originalUrl(bgFile), filename: bgFile['filename'] as String?, size: humanFileSize((bgFile['size'] as num?) ?? 0), downloadUrl: urls.originalUrl(bgFile)),
              onTapAvatar: avatarFile == null ? null : () => showImageViewer(c, imageUrl: urls.originalUrl(avatarFile), filename: avatarFile['filename'] as String?, size: humanFileSize((avatarFile['size'] as num?) ?? 0), downloadUrl: urls.originalUrl(avatarFile)),
            ),
          ),
          ProfileCell(span: 3, child: ProfileActions(data: data, serverId: widget.serverId, onClose: () => Navigator.of(c).maybePop())),
          ?_roles(c, data, widget.serverId),
          ?_status(c, data),
          ?_badges(c, data),
          _joined(c, data, widget.serverId),
          ..._mutuals(c, data, widget.serverId),
          ?_bio(c, data, full: true, cols: 3),
        ];
        return Dialog(
          backgroundColor: c.cs.surfaceContainerHigh,
          shape: RoundedRectangleBorder(borderRadius: br(Radius_.xl)),
          insetPadding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(child: ProfileGrid(cols: 3, cells: cells)),
          ),
        );
      },
    );
  }
}

/// Small profile popover shown when clicking an avatar/name (`UserCard`).
Future<void> showUserCard(BuildContext context, String userId, {String? serverId}) {
  final size = MediaQuery.sizeOf(context);
  if (screenClassOf(size) == ScreenClass.phone) return showUserProfile(context, userId, serverId: serverId);
  final store = context.read<ClientStore>();
  final settings = context.read<SettingsStore>();
  final box = context.findRenderObject();
  final anchor = box is RenderBox && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : Rect.fromLTWH(size.width / 2, size.height / 2, 0, 0);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 150),
    transitionBuilder: (c, a, _, child) => FadeTransition(opacity: a, child: child),
    pageBuilder: (c, _, _) => MultiProvider(
      providers: [ChangeNotifierProvider.value(value: store), ChangeNotifierProvider.value(value: settings)],
      child: _CardHost(userId: userId, serverId: serverId, anchor: anchor, parent: context),
    ),
  );
}

class _CardHost extends StatefulWidget {
  const _CardHost({required this.userId, required this.serverId, required this.anchor, required this.parent});
  final String userId;
  final String? serverId;
  final Rect anchor;
  final BuildContext parent;
  @override
  State<_CardHost> createState() => _CardHostState();
}

class _CardHostState extends State<_CardHost> {
  late final ProfileData data = ProfileData(context.read<ClientStore>(), widget.userId);

  @override
  void dispose() {
    data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    const w = 340.0, h = 400.0;
    var left = widget.anchor.right + 5;
    if (left + w > size.width - 8) left = widget.anchor.left - w - 5;
    left = left.clamp(8, size.width - w - 8).toDouble();
    final top = widget.anchor.top.clamp(8, size.height - h - 8).toDouble();
    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: w,
          height: h,
          child: ListenableBuilder(
            listenable: data,
            builder: (c, _) {
              void openFull() {
                Navigator.of(c).pop();
                showUserProfile(widget.parent, widget.userId, serverId: widget.serverId);
              }

              final cells = <ProfileCell>[
                ProfileCell(span: 2, child: ProfileBanner(data: data, serverId: widget.serverId, onTap: openFull)),
                ProfileCell(span: 2, child: ProfileActions(data: data, serverId: widget.serverId, onClose: () => Navigator.of(c).maybePop())),
                ?_roles(c, data, widget.serverId),
                ?_badges(c, data),
                ?_status(c, data),
                _joined(c, data, widget.serverId),
                ?_owner(c, data),
                ?_bio(c, data, full: false, onTap: openFull, cols: 2),
              ];
              return Material(
                color: c.cs.surfaceContainerHigh,
                elevation: 3,
                shadowColor: c.cs.shadow,
                borderRadius: br(Radius_.xl),
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(child: ProfileGrid(cols: 2, cells: cells)),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ----- sub dialogs -----

Future<void> showMutualFriends(BuildContext context, List<String> users, {String? serverId}) {
  final store = context.read<ClientStore>();
  return showAppDialog<void>(
    context,
    title: 'Mutual Friends',
    maxWidth: 420,
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final u in users)
            ListTile(
              leading: UserAvatar(userId: u, size: 36),
              title: Text(store.user(u)?['username'] as String? ?? '', overflow: TextOverflow.ellipsis),
              onTap: () => showUserProfile(context, u, serverId: serverId),
            ),
        ],
      ),
    ),
  );
}

Future<void> showMutualGroups(BuildContext context, List<Json> groups) {
  final store = context.read<ClientStore>();
  return showAppDialog<void>(
    context,
    title: 'Mutual Groups',
    maxWidth: 420,
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final g in groups)
            ListTile(
              leading: IconAvatar(url: store.api.fileUrl('icons', g['icon'] as Map?, width: 72), name: g['name'] as String? ?? '?', size: 36, square: g['_kind'] != 'server'),
              title: Text(g['name'] as String? ?? '', overflow: TextOverflow.ellipsis),
              onTap: () {
                Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
                if (g['_kind'] == 'server') {
                  context.goPath('/server/${g['_id']}');
                } else {
                  context.goPath('/channel/${g['_id']}');
                }
              },
            ),
        ],
      ),
    ),
  );
}

Future<void> showUserRoles(BuildContext context, String serverId, String userId) {
  final store = context.read<ClientStore>();
  final server = store.servers[serverId] ?? const {};
  final roles = (server['roles'] as Map?)?.cast<String, dynamic>() ?? const {};
  final edit = server['owner'] == store.userId || (store.canInServer(serverId, Perm.assignRoles) && store.inferiorToMe(serverId, userId));
  final display = store.members[serverId]?[userId]?['nickname'] as String? ?? store.displayName(userId);
  final allOrdered = roles.entries.map((e) => <String, dynamic>{...(e.value as Map).cast<String, dynamic>(), '_id': e.key}).toList()
    ..sort((a, b) => ((a['rank'] as num?) ?? 0).compareTo((b['rank'] as num?) ?? 0));
  final myTop = store.memberRoles(serverId, store.userId).firstOrNull;

  return showAppDialog<void>(
    context,
    title: edit ? "Edit $display's roles" : "$display's roles",
    maxWidth: 420,
    content: StatefulBuilder(
      builder: (c, set) {
        final mine = ((store.members[serverId]?[userId]?['roles'] as List?) ?? const []).cast<String>();
        Widget dot(Json r) => Container(width: 16, height: 16, decoration: BoxDecoration(color: parseCssColour(r['colour'] as String?) ?? c.cs.outlineVariant, shape: BoxShape.circle));
        if (!edit) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final r in store.memberRoles(serverId, userId).reversed)
                Row(children: [Expanded(child: Text(r['name'] as String? ?? '', overflow: TextOverflow.ellipsis)), dot(r)]),
            ],
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final r in allOrdered)
              CheckboxListTile(
                dense: true,
                value: mine.contains(r['_id']),
                onChanged: (server['owner'] != store.userId && ((r['rank'] as num?) ?? 0) < ((myTop?['rank'] as num?) ?? 0))
                    ? null
                    : (v) async {
                        final next = [...mine.where((x) => x != r['_id']), if (v == true) r['_id'] as String].where(roles.containsKey).toList();
                        try {
                          await store.api.patch('/servers/$serverId/members/$userId', {'roles': next});
                          (store.members[serverId]?[userId])?['roles'] = next;
                          store.refresh();
                          set(() {});
                        } catch (e) {
                          if (c.mounted) showSnack(c, errorText(e));
                        }
                      },
                title: Row(children: [Expanded(child: Text(r['name'] as String? ?? '', overflow: TextOverflow.ellipsis)), dot(r)]),
                controlAffinity: ListTileControlAffinity.leading,
              ),
          ],
        );
      },
    ),
  );
}

/// Add a bot to a server or group you manage (`AddBot` modal).
Future<void> showAddBot(BuildContext context, Json bot) {
  final store = context.read<ClientStore>();
  var filter = '';
  String? selected;
  String? kind;
  return showAppDialog<void>(
    context,
    title: 'Add Bot',
    maxWidth: 420,
    content: StatefulBuilder(
      builder: (c, set) {
        final servers = store.servers.values.where((s) => store.canInServer(s['_id'] as String, Perm.manageServer) && store.members[s['_id']]?[bot['_id']] == null).toList();
        final groups = store.channels.values.where((ch) => ch['channel_type'] == 'Group' && !((ch['recipients'] as List?) ?? const []).contains(bot['_id'])).toList();
        final items = <(Json, String)>[
          for (final s in servers) (s, 'server'),
          for (final g in groups) (g, 'group'),
        ].where((e) => ((e.$1['name'] as String?) ?? '').toLowerCase().contains(filter.toLowerCase())).toList()
          ..sort((a, b) => ((a.$1['name'] as String?) ?? '').compareTo((b.$1['name'] as String?) ?? ''));
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Column(
                spacing: 8,
                children: [
                  UserAvatar(userId: bot['_id'] as String?, size: 64, fallbackName: bot['username'] as String?),
                  Text(bot['username'] as String? ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                  Text('Registered since ${formatLongDate(ulidTime(bot['_id'] as String))}', style: TextStyle(fontSize: 12, color: c.cs.onSurfaceVariant)),
                ],
              ),
            ),
            if ((bot['description'] as String?)?.isNotEmpty ?? false)
              Container(
                constraints: const BoxConstraints(maxHeight: 120),
                margin: const EdgeInsets.only(top: Gap.md),
                padding: const EdgeInsets.all(Gap.md),
                decoration: BoxDecoration(color: c.cs.secondaryContainer, borderRadius: br(Radius_.lg)),
                child: SingleChildScrollView(child: RichContent(bot['description'] as String)),
              ),
            const SizedBox(height: Gap.md),
            TextField(decoration: const InputDecoration(hintText: 'Search for groups...'), onChanged: (v) => set(() => filter = v)),
            SizedBox(
              height: 200,
              child: ListView(
                children: [
                  for (final (g, k) in items)
                    ListTile(
                      selected: selected == g['_id'],
                      leading: IconAvatar(url: store.api.fileUrl('icons', g['icon'] as Map?, width: 48), name: g['name'] as String? ?? '?', size: 24, square: k != 'server'),
                      title: Text(g['name'] as String? ?? ''),
                      onTap: () => set(() {
                        selected = g['_id'] as String;
                        kind = k;
                      }),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Gap.sm),
            Text('Bots are not verified by DawnChat.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: c.cs.outline)),
            Text('The bot will not be granted any permissions.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: c.cs.outline)),
          ],
        );
      },
    ),
    actions: [
      const DlgAction('Cancel'),
      DlgAction('Add', onPressed: () async {
        if (selected == null) return false;
        await store.api.post('/bots/${bot['_id']}/invite', {kind == 'server' ? 'server' : 'group': selected});
        return null;
      }),
    ],
  );
}
