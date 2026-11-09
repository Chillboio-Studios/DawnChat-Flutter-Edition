import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../net_image.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../api/client_store.dart';
import '../../core/links.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../widgets.dart';
import 'settings_pages.dart';

class SettingsEntry {
  const SettingsEntry({
    this.id,
    required this.title,
    required this.icon,
    this.hidden = false,
    this.href,
    this.onTap,
    this.destructive = false,
  });
  final String? id;
  final String title;
  final IconData icon;
  final bool hidden;
  final String? href;
  final Future<void> Function(BuildContext context)? onTap;
  final bool destructive;
}

class SettingsCategory {
  const SettingsCategory(this.entries, {this.title});
  final String? title;
  final List<SettingsEntry> entries;
}

Future<void> showSettings(BuildContext context, {String? page}) {
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<ClientStore>(),
        child: SettingsPage(initialPage: page),
      ),
    ),
  );
}

bool get isDesktopPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS);

List<SettingsCategory> userSettingsList(BuildContext context) {
  final store = context.read<ClientStore>();
  final video = store.api.config?.video ?? true;
  return [
    SettingsCategory(title: 'User Settings', [
      const SettingsEntry(
        id: 'account',
        icon: Icons.manage_accounts_outlined,
        title: 'My Account',
        hidden: true,
      ),
      const SettingsEntry(
        id: 'profile',
        icon: Icons.account_circle_outlined,
        title: 'Profile',
      ),
      const SettingsEntry(
        id: 'sessions',
        icon: Icons.verified_user_outlined,
        title: 'Sessions',
      ),
    ]),
    const SettingsCategory(title: 'DawnChat', [
      SettingsEntry(
        id: 'bots',
        icon: Icons.smart_toy_outlined,
        title: 'My Bots',
      ),
      SettingsEntry(
        id: 'feedback',
        icon: Icons.rate_review_outlined,
        title: 'Feedback',
      ),
    ]),
    SettingsCategory(title: 'Client Settings', [
      SettingsEntry(
        id: 'voice',
        icon: Icons.mic_none,
        title: video ? 'Voice & Video' : 'Voice',
      ),
      const SettingsEntry(
        id: 'appearance',
        icon: Icons.palette_outlined,
        title: 'Appearance',
      ),
      const SettingsEntry(
        id: 'notifications',
        icon: Icons.notifications_none,
        title: 'Notifications',
      ),
      const SettingsEntry(
        id: 'language',
        icon: Icons.language,
        title: 'Language',
      ),
      SettingsEntry(
        id: 'native',
        icon: Icons.desktop_windows_outlined,
        title: 'Desktop',
        hidden: !isDesktopPlatform,
      ),
    ]),
    SettingsCategory([
      SettingsEntry(
        icon: Icons.campaign_outlined,
        title: "What's New",
        onTap: (c) => showChangelog(c),
      ),
      const SettingsEntry(
        icon: Icons.memory,
        title: 'We are a stoatchat based instance, View Source Code',
        href: sourceCodeUrl,
      ),
      const SettingsEntry(
        id: 'advanced',
        icon: Icons.science_outlined,
        title: 'Advanced',
      ),
      const SettingsEntry(
        icon: Icons.coffee_outlined,
        title: 'Donate',
        href: donationUrl,
      ),
      SettingsEntry(
        icon: Icons.logout,
        title: 'Log Out',
        destructive: true,
        onTap: (c) async {
          final s = c.read<ClientStore>();
          Navigator.of(c).pop();
          await s.logout();
        },
      ),
    ]),
  ];
}

String pageTitle(List<SettingsCategory> list, String id) {
  if (id.startsWith('bots/')) return 'My Bots';
  for (final c in list) {
    for (final e in c.entries) {
      if (e.id == id) return e.title;
    }
  }
  return '';
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.initialPage});
  final String? initialPage;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String? _page;
  bool _phoneDetail = false;

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage;
    _phoneDetail = widget.initialPage != null;
  }

  void _navigate(SettingsEntry e) async {
    if (e.onTap != null) {
      await e.onTap!(context);
    } else if (e.href != null) {
      openUrl(e.href!);
    } else if (e.id != null) {
      setState(() {
        _page = e.id;
        _phoneDetail = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final size = MediaQuery.sizeOf(context);
    final sc = screenClassOf(size);
    final list = userSettingsList(context);
    final phone = sc == ScreenClass.phone;
    final current = _page ?? (phone ? null : 'account');

    final sidebar = _Sidebar(
      list: list,
      page: current,
      onSelect: _navigate,
      onClose: () => Navigator.of(context).pop(),
    );
    final content = current == null
        ? const SizedBox.shrink()
        : _Content(
            title: pageTitle(list, current),
            page: current,
            onBack: phone ? () => setState(() => _phoneDetail = false) : null,
            onClose: () => Navigator.of(context).pop(),
            onNavigate: (p) => setState(() => _page = p),
            list: list,
          );

    return Scaffold(
      backgroundColor: cs.surfaceContainerHigh,
      body: SafeArea(
        child: phone
            ? (_phoneDetail && current != null ? content : sidebar)
            : Row(
                children: [
                  Expanded(
                    flex: 218,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: 230,
                          maxWidth: 300,
                        ),
                        child: sidebar,
                      ),
                    ),
                  ),
                  Expanded(flex: 800, child: content),
                ],
              ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.list,
    required this.page,
    required this.onSelect,
    required this.onClose,
  });
  final List<SettingsCategory> list;
  final String? page;
  final void Function(SettingsEntry) onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final store = context.watch<ClientStore>();
    final phone = MediaQuery.sizeOf(context).width <= 600;
    final info = PackageInfo.fromPlatform();
    return ListView(
      padding: EdgeInsets.fromLTRB(phone ? 12 : 8, phone ? 8 : 74, 8, 8),
      children: [
        if (phone)
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton.filledTonal(
              icon: const Icon(Icons.close),
              onPressed: onClose,
            ),
          ),
        _AccountCard(
          selected: page == 'account',
          onTap: () => onSelect(
            const SettingsEntry(
              id: 'account',
              icon: Icons.person,
              title: 'My Account',
            ),
          ),
        ),
        const SizedBox(height: Gap.md),
        for (final cat in list)
          if (cat.entries.any((e) => !e.hidden)) ...[
            if (cat.title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 8, 4),
                child: Text(
                  cat.title!.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: cs.outline,
                  ),
                ),
              ),
            for (final e in cat.entries)
              if (!e.hidden)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Material(
                    color: page?.split('/').first == e.id
                        ? cs.secondaryContainer
                        : Colors.transparent,
                    borderRadius: br(Radius_.xl),
                    child: InkWell(
                      borderRadius: br(Radius_.xl),
                      onTap: () => onSelect(e),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              e.icon,
                              size: 20,
                              color: e.destructive
                                  ? cs.error
                                  : (page?.split('/').first == e.id
                                        ? cs.onSecondaryContainer
                                        : cs.onSurfaceVariant),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                e.title,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: e.destructive
                                      ? cs.error
                                      : (page?.split('/').first == e.id
                                            ? cs.onSecondaryContainer
                                            : cs.onSurfaceVariant),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
          ],
        const SizedBox(height: 16),
        FutureBuilder<PackageInfo>(
          future: info,
          builder: (c, s) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: 'Version: ',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: s.data?.version ?? ''),
                ],
              ),
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
        ),
        if (store.api.config?.legalLinks.isNotEmpty ?? false)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: Wrap(
              spacing: 8,
              children: [
                for (final l in const [
                  ('terms_of_service', 'Terms'),
                  ('privacy_policy', 'Privacy'),
                  ('guidelines', 'Guidelines'),
                ])
                  if (store.api.config!.legalLinks[l.$1] != null)
                    InkWell(
                      onTap: () =>
                          openUrl(store.api.config!.legalLinks[l.$1] as String),
                      child: Text(
                        l.$2,
                        style: TextStyle(fontSize: 11, color: cs.outline),
                      ),
                    ),
              ],
            ),
          ),
      ],
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.selected, required this.onTap});
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final cs = context.cs;
    final me = store.me;
    final banner = store.api.fileUrl(
      'backgrounds',
      (me?['profile'] as Map?)?['background'] as Map?,
      width: 480,
    );
    return Material(
      color: selected ? cs.secondaryContainer : cs.surfaceContainerHighest,
      borderRadius: br(Radius_.xl),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: banner != null
              ? BoxDecoration(
                  image: DecorationImage(
                    image: netImageProvider(banner),
                    fit: BoxFit.cover,
                    colorFilter: const ColorFilter.mode(
                      Colors.black38,
                      BlendMode.darken,
                    ),
                  ),
                )
              : null,
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              UserAvatar(userId: store.userId, size: 40, showStatus: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      store.displayName(store.userId),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: banner != null ? Colors.white : null,
                      ),
                    ),
                    Text(
                      '${me?['username']}#${me?['discriminator']}',
                      style: TextStyle(
                        fontSize: 12,
                        color: banner != null
                            ? Colors.white70
                            : cs.onSurfaceVariant,
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
  }
}

class _Content extends StatelessWidget {
  const _Content({
    required this.title,
    required this.page,
    required this.onClose,
    required this.onNavigate,
    required this.list,
    this.onBack,
  });
  final String title, page;
  final VoidCallback onClose;
  final VoidCallback? onBack;
  final void Function(String) onNavigate;
  final List<SettingsCategory> list;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final phone = MediaQuery.sizeOf(context).width <= 600;
    final tablet =
        screenClassOf(MediaQuery.sizeOf(context)) != ScreenClass.desktop;
    final parts = page.split('/');
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: phone
            ? null
            : const BorderRadius.horizontal(left: Radius.circular(30)),
      ),
      child: Stack(
        children: [
          SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              tablet ? 12 : 32,
              tablet ? 12 : 80,
              tablet ? 12 : 32,
              80,
            ),
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 740),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (page != 'account')
                      Padding(
                        padding: const EdgeInsets.only(bottom: 13),
                        child: Row(
                          children: [
                            if (onBack != null)
                              IconButton(
                                icon: const Icon(Icons.arrow_back),
                                onPressed: onBack,
                              ),
                            for (var i = 0; i < parts.length; i++) ...[
                              if (i > 0)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  child: Icon(
                                    Icons.chevron_right,
                                    size: 18,
                                    color: cs.outline,
                                  ),
                                ),
                              InkWell(
                                onTap: i < parts.length - 1
                                    ? () => onNavigate(
                                        parts.sublist(0, i + 1).join('/'),
                                      )
                                    : null,
                                child: Text(
                                  i == 0 ? title : parts[i],
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: i == parts.length - 1
                                        ? cs.onSurface
                                        : cs.outline,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      )
                    else if (onBack != null)
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: onBack,
                      ),
                    SettingsBody(page: page, onNavigate: onNavigate),
                  ],
                ),
              ),
            ),
          ),
          if (!phone && !tablet)
            Positioned(
              right: 12,
              top: 80,
              child: Column(
                children: [
                  IconButton.filledTonal(
                    icon: const Icon(Icons.close),
                    onPressed: onClose,
                  ),
                  Text(
                    'ESC',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          if (tablet && !phone)
            Positioned(
              right: 12,
              bottom: 12,
              child: IconButton.filledTonal(
                icon: const Icon(Icons.close),
                onPressed: onClose,
              ),
            ),
        ],
      ),
    );
  }
}
