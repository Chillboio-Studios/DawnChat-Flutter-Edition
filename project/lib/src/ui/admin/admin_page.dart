import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/client_store.dart';
import '../../core/i18n.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../router.dart';
import '../settings/settings_page.dart';
import 'changelog_admin.dart';
import 'pages/announce_page.dart';
import 'pages/legal_page.dart';
import 'pages/policy_page.dart';
import 'pages/audit_page.dart';
import 'pages/ban_records_page.dart';
import 'pages/bans_page.dart';
import 'pages/bots_page.dart';
import 'pages/content_page.dart';
import 'pages/deleted_page.dart';
import 'pages/diagnostics_page.dart';
import 'pages/disabled_page.dart';
import 'pages/history_page.dart';
import 'pages/lookup_page.dart';
import 'pages/overview_page.dart';
import 'pages/reports_page.dart';
import 'pages/servers_page.dart';
import 'pages/staff_page.dart';
import 'pages/strikes_page.dart';
import 'pages/tickets_page.dart';
import 'pages/users_page.dart';

/// Platform admin panel — settings-style shell with grouped sections.
/// Sections are gated by the caller's admin permission bitfield
/// (or `privileged` for full access).
///
/// Deep links: `/admin?s=<section>&uid=<user>&rid=<report>&tid=<ticket>&id=<lookup>`
class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

/// Nav group: (id, title, icon, permission-gated, builder)
typedef _Section = ({
  String id,
  String title,
  IconData icon,
  bool Function(ClientStore) visible,
  Widget Function(Map<String, String> qp) build,
});


final List<({String? group, List<_Section> sections})> _navGroups = [
  (
    group: null,
    sections: [
      (
        id: 'overview',
        title: 'Overview',
        icon: Icons.dashboard_outlined,
        visible: (s) => s.canAdmin(ClientStore.adminViewAudit),
        build: (_) => const OverviewView(),
      ),
    ],
  ),
  (
    group: 'Moderation',
    sections: [
      (
        id: 'reports',
        title: 'Reports',
        icon: Icons.flag_outlined,
        visible: (s) => s.canAdmin(ClientStore.adminViewReports),
        build: (qp) => ReportsView(focusReportId: qp['rid']),
      ),
      (
        id: 'tickets',
        title: 'Tickets',
        icon: Icons.support_agent_outlined,
        visible: (s) => s.canAdmin(ClientStore.adminViewReports),
        build: (qp) => TicketsView(focusTicketId: qp['tid']),
      ),
      (
        id: 'strikes',
        title: 'Strikes',
        icon: Icons.gavel_outlined,
        visible: (s) =>
            s.canAdmin(ClientStore.adminViewReports) ||
            s.canAdmin(ClientStore.adminManageReports),
        build: (_) => const StrikesView(),
      ),
      (
        id: 'bans',
        title: 'Bans',
        icon: Icons.block_outlined,
        visible: (s) =>
            s.canAdmin(ClientStore.adminViewUsers) &&
            s.canAdmin(ClientStore.adminBanUsers),
        build: (_) => const BansView(),
      ),
      (
        id: 'ban_records',
        title: 'Ban Records',
        icon: Icons.list_alt_outlined,
        visible: (s) => s.canAdmin(ClientStore.adminBanUsers),
        build: (_) => const BanRecordsView(),
      ),
      (
        id: 'content',
        title: 'Content',
        icon: Icons.forum_outlined,
        visible: (s) =>
            s.canAdmin(ClientStore.adminViewReports) ||
            s.canAdmin(ClientStore.adminManageReports),
        build: (_) => const ContentModView(),
      ),
    ],
  ),
  (
    group: 'People',
    sections: [
      (
        id: 'users',
        title: 'Users',
        icon: Icons.people_outline,
        visible: (s) => s.canAdmin(ClientStore.adminViewUsers),
        build: (qp) => UsersView(focusUserId: qp['uid']),
      ),
      (
        id: 'staff',
        title: 'Staff',
        icon: Icons.badge_outlined,
        visible: (s) => s.canAdmin(ClientStore.adminEditUsers),
        build: (qp) => StaffView(focusUserId: qp['uid']),
      ),
      (
        id: 'disabled',
        title: 'Disabled',
        icon: Icons.pause_circle_outline,
        visible: (s) => s.canAdmin(ClientStore.adminViewUsers),
        build: (qp) => DisabledView(focusUserId: qp['uid']),
      ),
      (
        id: 'deleted',
        title: 'Deleted',
        icon: Icons.person_off_outlined,
        visible: (s) => s.canAdmin(ClientStore.adminViewUsers),
        build: (qp) => DeletedView(focusUserId: qp['uid']),
      ),
      (
        id: 'lookup',
        title: 'Lookup',
        icon: Icons.search_outlined,
        visible: (s) => s.canAdmin(ClientStore.adminViewUsers),
        build: (qp) => LookupView(initialId: qp['id']),
      ),
    ],
  ),
  (
    group: 'Platform',
    sections: [
      (
        id: 'servers',
        title: 'Servers',
        icon: Icons.dns_outlined,
        visible: (s) =>
            s.canAdmin(ClientStore.adminViewServers) ||
            s.canAdmin(ClientStore.adminEditServers),
        build: (_) => const ServersView(),
      ),
      (
        id: 'bots',
        title: 'Bots',
        icon: Icons.smart_toy_outlined,
        visible: (s) =>
            s.canAdmin(ClientStore.adminViewUsers) ||
            s.canAdmin(ClientStore.adminEditUsers),
        build: (_) => const BotsView(),
      ),
    ],
  ),
  (
    group: 'System',
    sections: [
      (
        id: 'audit',
        title: 'Audit Log',
        icon: Icons.history,
        visible: (s) => s.canAdmin(ClientStore.adminViewAudit),
        build: (_) => const AuditView(),
      ),
      (
        id: 'history',
        title: 'History',
        icon: Icons.manage_history_outlined,
        visible: (s) => s.canAdmin(ClientStore.adminViewAudit),
        build: (_) => const HistoryView(),
      ),
      (
        id: 'legal',
        title: 'Legal',
        icon: Icons.gavel,
        visible: (s) => s.canAdmin(ClientStore.adminViewAudit),
        build: (_) => const LegalView(),
      ),
      (
        id: 'diagnostics',
        title: 'Diagnostics',
        icon: Icons.monitor_heart_outlined,
        visible: (s) => s.canAdmin(ClientStore.adminViewAudit),
        build: (_) => const DiagnosticsView(),
      ),
    ],
  ),
  (
    group: 'Broadcast',
    sections: [
      (
        id: 'announce',
        title: 'Announce',
        icon: Icons.campaign,
        visible: (s) => s.canAdmin(ClientStore.adminBroadcast),
        build: (_) => const AnnounceView(),
      ),
      (
        id: 'changelogs',
        title: 'Changelogs',
        icon: Icons.campaign_outlined,
        visible: (s) => s.canAdmin(ClientStore.adminBroadcast),
        build: (_) => const ChangelogsView(),
      ),
      (
        id: 'policy',
        title: 'Policy',
        icon: Icons.gavel_outlined,
        visible: (s) => s.canAdmin(ClientStore.adminBroadcast),
        build: (_) => const PolicyView(),
      ),
    ],
  ),
];

class _AdminPageState extends State<AdminPage> {
  String? _sectionOverride;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final cs = context.cs;
    final phone =
        screenClassOf(MediaQuery.sizeOf(context)) == ScreenClass.phone;
    final qp = GoRouterState.of(context).uri.queryParameters;

    // Build visible sections grouped for the sidebar.
    final groups = <(String?, List<_Section>)>[
      for (final g in _navGroups)
        (
          g.group,
          [for (final s in g.sections) if (s.visible(store)) s],
        ),
    ].where((g) => g.$2.isNotEmpty).toList();
    final visible = [for (final g in groups) ...g.$2];

    if (visible.isEmpty) {
      return Scaffold(
        body: Center(
          child: Text(
            tr('You do not have permission to access the admin panel.'),
          ),
        ),
      );
    }

    final requested = qp['s'] ?? _sectionOverride;
    final section = visible.any((s) => s.id == requested)
        ? requested!
        : visible.first.id;
    final current = visible.firstWhere((s) => s.id == section);

    Widget navRow(_Section s) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: SettingsNavRow(
        icon: s.icon,
        title: tr(s.title),
        selected: section == s.id,
        onTap: () => setState(() => _sectionOverride = s.id),
      ),
    );

    final nav = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final g in groups) ...[
          if (g.$1 != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
              child: Text(
                tr(g.$1!).toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: cs.outline,
                ),
              ),
            ),
          for (final s in g.$2) navRow(s),
        ],
      ],
    );

    final body = current.build(qp);

    if (phone) {
      return Scaffold(
        appBar: AppBar(
          title: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: section,
              isDense: true,
              items: [
                for (final g in groups)
                  for (final s in g.$2)
                    DropdownMenuItem(value: s.id, child: Text(tr(s.title))),
              ],
              onChanged: (v) =>
                  setState(() => _sectionOverride = v ?? section),
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.goPath('/app'),
          ),
        ),
        body: SafeArea(child: body),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 240,
            child: ListView(
              padding: const EdgeInsets.all(Gap.md),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: Gap.md),
                  child: Row(
                    children: [
                      Icon(
                        Icons.admin_panel_settings_outlined,
                        color: cs.primary,
                      ),
                      const SizedBox(width: Gap.sm),
                      Text(
                        tr('Admin'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                nav,
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Container(
              color: cs.surface,
              child: body,
            ),
          ),
        ],
      ),
    );
  }
}
