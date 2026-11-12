import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/client_store.dart';
import '../../core/links.dart';
import '../../router.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../settings/settings_page.dart';
import '../widgets.dart';
import '../menus/context_menu.dart';
import '../menus/user_menu.dart';
import '../modals/server_modals.dart';
import '../profile/profile.dart' show showUserProfile;
import 'server_channels_screen.dart';
import '../../core/i18n.dart';

/// Primary page header shared by Home, Friends and channels.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.icon,
    required this.title,
    this.actions = const [],
    this.subtitle,
    this.leading,
  });
  final Widget icon;
  final Widget title;
  final Widget? subtitle;
  final List<Widget> actions;

  /// Replaces the phone drawer button when set (e.g. a back button).
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final isPhone = MediaQuery.sizeOf(context).width <= 600;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: Gap.md),
      color: cs.surfaceContainerLow,
      child: Row(
        children: [
          if (isPhone)
            leading ??
                IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.maybeOf(context)?.openDrawer(),
                ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.md),
            child: IconTheme(
              data: IconThemeData(color: cs.onSurfaceVariant, size: 22),
              child: icon,
            ),
          ),
          Expanded(
            child: DefaultTextStyle.merge(
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              overflow: TextOverflow.ellipsis,
              child: Row(
                children: [
                  Flexible(child: title),
                  if (subtitle != null)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: DefaultTextStyle.merge(
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: cs.outline,
                          ),
                          overflow: TextOverflow.ellipsis,
                          child: subtitle!,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final cs = context.cs;
    final inLounge = store.servers.containsKey(loungeServerId);
    final w = MediaQuery.sizeOf(context).width;

    Widget tile(IconData icon, String title, String desc, VoidCallback onTap) =>
        Material(
          color: cs.surfaceContainerHigh,
          borderRadius: br(Radius_.md),
          child: InkWell(
            borderRadius: br(Radius_.md),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: br(Radius_.md),
                    ),
                    child: Icon(icon, color: cs.onPrimaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          desc,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

    final left = [
      tile(
        Icons.add_circle,
        tr('Create a group or server'),
        tr(
          'Invite all of your friends, some cool bots, and throw a big party.',
        ),
        () => showCreateOrJoinServer(context),
      ),
      tile(
        Icons.groups_3,
        inLounge ? 'Go to the DawnChat Lounge' : 'Join the DawnChat Lounge',
        tr(
          'You can report issues and discuss improvements with us directly here.',
        ),
        () async {
          if (inLounge) {
            context.goPath('/server/$loungeServerId');
          } else {
            context.goPath('/invite/Testers');
          }
        },
      ),
      tile(
        Icons.payments,
        tr('Donate to DawnChat'),
        tr('Support the project by donating - thank you!'),
        () => openUrl(donationUrl),
      ),
    ];
    final right = [
      tile(
        Icons.explore,
        tr('Discover DawnChat'),
        tr('Find a community based on your hobbies or interests.'),
        () => context.goPath('/discover'),
      ),
      tile(
        Icons.rate_review,
        tr('Give feedback on DawnChat'),
        tr('Let us know how we can improve our app by giving us feedback.'),
        () => showSettings(context, page: 'feedback'),
      ),
      tile(
        Icons.settings,
        tr('Open settings'),
        tr('You can also click the gear icon in the bottom left.'),
        () => showSettings(context),
      ),
    ];

    return Column(
      children: [
        PageHeader(icon: Icon(Icons.home), title: Text(tr('Home'))),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 12),
            children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(
                      Colors.white.withValues(alpha: .12),
                      cs.surface,
                    ),
                    borderRadius: br(Radius_.xl),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Wordmark(width: w * .78 < 480 ? w * .78 : 480),
                ),
              ),
              const SizedBox(height: 32),
              Center(
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: w <= 640 ? 360 : 560 + 36,
                  ),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: br(Radius_.md),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: w <= 640
                      ? Column(
                          children: [
                            for (final t in [...left, ...right])
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: t,
                              ),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  for (final t in left)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: t,
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                children: [
                                  for (final t in right)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: t,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Scaffold(
      backgroundColor: cs.surfaceContainerLow,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Wordmark(width: 300),
            const SizedBox(height: 24),
            Container(
              constraints: const BoxConstraints(maxWidth: 560),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cs.errorContainer,
                border: Border.all(color: cs.error),
                borderRadius: br(Radius_.md),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '404 page could not be found',
                    style: TextStyle(
                      color: cs.onErrorContainer,
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'The page you requested does not exist.',
                    style: TextStyle(color: cs.onErrorContainer),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => context.go(context.href('/app')),
                    child: const Text('Go to Home'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});
  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  String _page = 'online';

  static int _pending(ClientStore store) {
    final n = store.incomingRequests.length;
    return n > 99 ? 99 : n;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final cs = context.cs;

    List<Json> sorted(List<Json> l) => [...l]
      ..sort((a, b) {
        final an = store.displayName(a['_id'] as String).toLowerCase();
        final bn = store.displayName(b['_id'] as String).toLowerCase();
        return an.compareTo(bn);
      });

    final friends = sorted(store.friends);
    final lists = <String, List<Json>>{
      'online': friends.where((u) => u['online'] == true).toList(),
      'all': friends,
      'incoming': sorted(store.incomingRequests),
      'outgoing': sorted(store.outgoingRequests),
      'blocked': sorted(store.blocked),
    };

    final pending = _pending(store);
    final railItems = <(String, String, IconData, int?)>[
      ('online', 'Online', Icons.waving_hand_outlined, null),
      ('all', 'All', Icons.all_inbox_outlined, null),
      (
        'pending',
        'Pending',
        Icons.notifications_outlined,
        pending > 0 ? pending : null,
      ),
      ('blocked', 'Blocked', Icons.block_outlined, null),
    ];

    Widget people(String title, List<Json> users) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            '$title – ${users.length}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: cs.outline,
            ),
          ),
        ),
        if (users.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('Nobody here right now!'),
          )
        else
          for (final u in users) _FriendEntry(user: u, page: _page),
      ],
    );

    final content = switch (_page) {
      'all' => people('All', lists['all']!),
      'pending' => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          people('Incoming', lists['incoming']!),
          people('Outgoing', lists['outgoing']!),
        ],
      ),
      'blocked' => people('Blocked', lists['blocked']!),
      _ => people('Online', lists['online']!),
    };

    final isNarrow = MediaQuery.sizeOf(context).width < 720;

    Future<void> addFriend() async {
      final name = await promptText(
        context,
        tr('Add a friend'),
        label: 'Username#0000',
        action: tr('Send request'),
      );
      if (name == null || name.isEmpty) return;
      try {
        await store.addFriend(name);
        if (context.mounted) showSnack(context, 'Friend request sent');
      } catch (e) {
        if (context.mounted) showSnack(context, errorText(e));
      }
    }

    final header = Column(
      children: [
        PageHeader(
          icon: const Icon(Icons.group),
          title: Text(tr('Friends')),
          actions: [
            IconButton.filled(
              tooltip: tr('Add a new friend'),
              icon: const Icon(Icons.add),
              onPressed: addFriend,
            ),
          ],
        ),
        if (isNarrow)
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final (id, label, icon, badge) in railItems)
                  _RailChip(
                    icon: icon,
                    label: tr(label),
                    badge: badge,
                    selected: _page == id,
                    onTap: () => setState(() => _page = id),
                  ),
              ],
            ),
          ),
      ],
    );

    final body = SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: content,
    );

    if (isNarrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [header, const Divider(height: 1), Expanded(child: body)],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left rail — matches the web client's NavigationRail.
        SizedBox(
          width: 200,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    for (final (id, label, icon, badge) in railItems)
                      _RailItem(
                        icon: icon,
                        label: tr(label),
                        badge: badge,
                        selected: _page == id,
                        onTap: () => setState(() => _page = id),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        VerticalDivider(width: 1, color: cs.outlineVariant),
        Expanded(
          child: Column(children: [header, Expanded(child: body)]),
        ),
      ],
    );
  }
}

/// Compact horizontal chip used by the friends rail on narrow screens.
class _RailChip extends StatelessWidget {
  const _RailChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
  });
  final IconData icon;
  final String label;
  final int? badge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final fg = selected ? cs.onSecondaryContainer : cs.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
      child: Material(
        color: selected ? cs.secondaryContainer : cs.surfaceContainerHighest,
        borderRadius: br(Radius_.xl),
        child: InkWell(
          borderRadius: br(Radius_.xl),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: fg,
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: br(Radius_.md),
                    ),
                    child: Text(
                      '$badge',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: cs.onPrimary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
  });
  final IconData icon;
  final String label;
  final int? badge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final fg = selected ? cs.onSecondaryContainer : cs.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected ? cs.secondaryContainer : Colors.transparent,
        borderRadius: br(Radius_.xl),
        child: InkWell(
          borderRadius: br(Radius_.xl),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: 20, color: fg),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w500, color: fg),
                  ),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: br(Radius_.md),
                    ),
                    child: Text(
                      '$badge',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: cs.onPrimary,
                      ),
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

class _FriendEntry extends StatelessWidget {
  const _FriendEntry({required this.user, required this.page});
  final Json user;
  final String page;

  @override
  Widget build(BuildContext context) {
    final store = context.read<ClientStore>();
    final cs = context.cs;
    final id = user['_id'] as String;
    final isFriend = user['relationship'] == 'Friend';
    void openMenu(Offset pos) =>
        showContextMenu(context, pos, userMenu(context, id));
    return GestureDetector(
      onSecondaryTapUp: (d) => openMenu(d.globalPosition),
      onLongPressStart: (d) => openMenu(d.globalPosition),
      child: InkWell(
        onTap: isFriend
            ? () async {
                final dm = await store.openDm(id);
                if (context.mounted) context.goPath('/channel/${dm['_id']}');
              }
            : () => showUserProfile(context, id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          child: Row(
            children: [
              UserAvatar(userId: id, size: 36, showStatus: isFriend),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  store.displayName(id),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              if (page == 'pending' && user['relationship'] == 'Incoming')
                IconButton(
                  icon: const Icon(Icons.check, size: 20),
                  tooltip: tr('Accept'),
                  onPressed: () => store.acceptFriend(id),
                )
              else if (page == 'pending')
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: tr('Decline'),
                  onPressed: () => store.removeFriend(id),
                )
              else if (page == 'blocked')
                IconButton(
                  icon: const Icon(Icons.lock_open_outlined, size: 20),
                  tooltip: tr('Unblock'),
                  onPressed: () => store.unblockUser(id),
                )
              else
                IconButton(
                  icon: Icon(
                    isFriend
                        ? Icons.person_remove_outlined
                        : Icons.block_outlined,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
                  tooltip: isFriend ? tr('Remove friend') : tr('Block'),
                  onPressed: () async {
                    if (isFriend) {
                      await store.removeFriend(id);
                    } else {
                      await store.blockUser(id);
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ServerHome extends StatelessWidget {
  const ServerHome({super.key, required this.serverId});
  final String serverId;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final server = store.servers[serverId];
    if (server == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.goPath('/');
      });
      return const SizedBox.shrink();
    }
    // On phones the server route is the channel-list screen (the Android
    // app's `ServerChannelsScreen`); wider layouts redirect to a channel.
    if (screenClassOf(MediaQuery.sizeOf(context)) == ScreenClass.phone) {
      return ServerChannelsScreen(serverId: serverId);
    }
    final chans = store
        .channelsOfServer(serverId)
        .where((c) => c['channel_type'] == 'TextChannel')
        .toList();
    if (chans.isNotEmpty) {
      // Sub-routes (channel pages) stack on top of this route; only the topmost one may redirect.
      if (ModalRoute.of(context)?.isCurrent ?? true) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted && (ModalRoute.of(context)?.isCurrent ?? true)) {
            context.goPath('/server/$serverId/channel/${chans.first['_id']}');
          }
        });
      }
      return const SizedBox.shrink();
    }
    return const Center(child: Text('No channels!'));
  }
}
