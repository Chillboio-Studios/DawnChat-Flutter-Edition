import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/client_store.dart';
import '../../core/links.dart';
import '../../router.dart';
import '../../theme/tokens.dart';
import '../settings/settings_page.dart';
import '../widgets.dart';
import '../modals/server_modals.dart';
import '../../core/i18n.dart';

/// Primary page header shared by Home, Friends and channels.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.icon,
    required this.title,
    this.actions = const [],
    this.subtitle,
  });
  final Widget icon;
  final Widget title;
  final Widget? subtitle;
  final List<Widget> actions;

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
        tr('Invite all of your friends, some cool bots, and throw a big party.'),
        () => showCreateOrJoinServer(context),
      ),
      tile(
        Icons.groups_3,
        inLounge ? 'Go to the DawnChat Lounge' : 'Join the DawnChat Lounge',
        tr('You can report issues and discuss improvements with us directly here.'),
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
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final cs = context.cs;
    final lists = [
      store.friends.where((u) => u['online'] == true).toList(),
      store.friends,
      store.incomingRequests,
      store.outgoingRequests,
      store.blocked,
    ];
    final names = ['Online', 'All', 'Pending', 'Outgoing', 'Blocked'];
    final list = lists[_tab];

    return Column(
      children: [
        PageHeader(
          icon: const Icon(Icons.group),
          title: Text(tr('Friends')),
          actions: [
            IconButton(
              tooltip: tr('Add friend'),
              icon: const Icon(Icons.person_add_alt_1),
              onPressed: () async {
                final name = await promptText(
                  context,
                  'Add a friend',
                  label: 'Username#0000',
                  action: 'Send request',
                );
                if (name == null || name.isEmpty) return;
                try {
                  await store.addFriend(name);
                  if (context.mounted) {
                    showSnack(context, 'Friend request sent');
                  }
                } catch (e) {
                  if (context.mounted) showSnack(context, errorText(e));
                }
              },
            ),
          ],
        ),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (var i = 0; i < names.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
                  child: ChoiceChip(
                    label: Text(
                      '${names[i]}${lists[i].isNotEmpty && i >= 2 ? ' (${lists[i].length})' : ''}',
                    ),
                    selected: _tab == i,
                    onSelected: (_) => setState(() => _tab = i),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Text(
                    'Nothing here.',
                    style: TextStyle(color: cs.outline),
                  ),
                )
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (c, i) {
                    final u = list[i];
                    final id = u['_id'] as String;
                    return ListTile(
                      leading: UserAvatar(
                        userId: id,
                        size: 40,
                        showStatus: true,
                      ),
                      title: Text(store.displayName(id)),
                      subtitle: Text('${u['username']}#${u['discriminator']}'),
                      onTap: () async {
                        if (_tab > 1) return;
                        final dm = await store.openDm(id);
                        if (context.mounted) {
                          context.goPath('/channel/${dm['_id']}');
                        }
                      },
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_tab == 2)
                            IconButton(
                              icon: const Icon(Icons.check),
                              onPressed: () => store.acceptFriend(id),
                            ),
                          if (_tab == 4)
                            IconButton(
                              icon: const Icon(Icons.lock_open),
                              tooltip: 'Unblock',
                              onPressed: () => store.unblockUser(id),
                            )
                          else
                            IconButton(
                              icon: Icon(
                                _tab == 2 || _tab == 3
                                    ? Icons.close
                                    : Icons.person_remove_outlined,
                              ),
                              onPressed: () => store.removeFriend(id),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
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
