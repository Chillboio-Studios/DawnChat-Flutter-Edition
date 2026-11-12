import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../api/client_store.dart';
import '../../api/permissions.dart';
import '../../push/push_service.dart';
import '../../router.dart';
import '../../state/settings_store.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../voice/voice_manager.dart';
import '../channel/channel_sidebars.dart';
import '../channel/composer.dart';
import '../channel/message_list.dart';
import '../modals/channel_modals.dart';
import '../settings/channel_settings.dart';
import '../voice/voice_ui.dart';
import '../widgets.dart';
import 'home_page.dart' show PageHeader;
import '../../core/i18n.dart';

const _memberSidebarKey = 'member_sidebar';
const _matureKey = 'mature';

enum _SidebarMode { members, search, pins }

class ChannelPage extends StatelessWidget {
  const ChannelPage({super.key, required this.channelId, this.messageId});
  final String channelId;
  final String? messageId;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final channel = store.channels[channelId];
    if (!store.ready) return const Center(child: CircularProgressIndicator());
    if (channel == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.goPath('/');
      });
      return const Center(child: CircularProgressIndicator());
    }
    return _AgeGate(
      enabled: channel['nsfw'] == true,
      contentId: channelId,
      contentName: '#${channel['name']}',
      child: TextChannelView(
        key: ValueKey('chan-$channelId'),
        channel: channel,
        messageId: messageId,
      ),
    );
  }
}

class TextChannelView extends StatefulWidget {
  const TextChannelView({super.key, required this.channel, this.messageId});
  final Json channel;
  final String? messageId;

  @override
  State<TextChannelView> createState() => _TextChannelViewState();
}

class _TextChannelViewState extends State<TextChannelView> {
  final _listCtl = MessageListController();
  _SidebarMode mode = _SidebarMode.members;
  String query = '';
  late final PushService _push;

  String get id => widget.channel['_id'] as String;
  String? get serverId => widget.channel['server'] as String?;
  String get type => widget.channel['channel_type'] as String;
  bool get hasSidebar => type != 'SavedMessages' && type != 'DirectMessage';

  @override
  void initState() {
    super.initState();
    _push = context.read<PushService>()..activeChannel = id;
  }

  @override
  void dispose() {
    if (_push.activeChannel == id) _push.activeChannel = null;
    super.dispose();
  }

  /// Alt+↑/↓ — cycle text channels within the current server, matching the
  /// web client's `NAVIGATION_CHANNEL_UP/DOWN` keybinds.
  void _navChannel(int dir) {
    final sid = serverId;
    if (sid == null) return;
    final list = context.read<ClientStore>().channelsOfServer(sid)
        .where(
          (c) =>
              c['channel_type'] != 'VoiceChannel' && c['voice'] == null,
        )
        .toList();
    if (list.isEmpty) return;
    final i = list.indexWhere((c) => c['_id'] == id);
    final next = list[(i + dir + list.length) % list.length];
    context.goPath('/server/$sid/channel/${next['_id']}');
  }

  /// Ctrl+Alt+↑/↓ — cycle servers, matching `NAVIGATION_SERVER_UP/DOWN`.
  void _navServer(int dir) {
    final store = context.read<ClientStore>();
    final sid = serverId;
    if (sid == null) return;
    final list = store.serverList;
    if (list.length < 2) return;
    final i = list.indexWhere((s) => s['_id'] == sid);
    if (i < 0) return;
    final next = list[(i + dir + list.length) % list.length];
    context.goPath('/server/${next['_id']}');
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final settings = context.watch<SettingsStore>();
    final cs = context.cs;
    final sc = screenClassOf(MediaQuery.sizeOf(context));
    final c = widget.channel;
    final canCall =
        store.isVoice(c) &&
        store.can(id, Perm.connect) &&
        type != 'SavedMessages';
    final showCard =
        canCall && (type == 'TextChannel' ? c['voice'] != null : true);
    final memberVisible =
        hasSidebar && settings.sectionState(_memberSidebarKey, true);
    final side = mode != _SidebarMode.members;

    final main = Column(
      children: [
        if (showCard) VoiceCallCardSlot(channel: c),
        Expanded(
          child: MessageList(
            channel: c,
            highlightId: widget.messageId,
            controller: _listCtl,
          ),
        ),
        CompositionInfoBar(channel: c),
        MessageComposer(channel: c, onSent: _listCtl.jumpToBottom),
      ],
    );

    Widget? sidebar;
    if (side) {
      sidebar = SizedBox(
        width: sc == ScreenClass.phone ? double.infinity : 360,
        child: Padding(
          padding: const EdgeInsets.only(right: Gap.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(Gap.md),
                child: Text(
                  mode == _SidebarMode.search
                      ? 'Search Results'
                      : 'Pinned Messages',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
                  ),
                ),
              ),
              Expanded(
                child: mode == _SidebarMode.search
                    ? SearchSidebar(channel: c, query: query)
                    : SearchSidebar(channel: c, pinned: true),
              ),
            ],
          ),
        ),
      );
    } else if (memberVisible &&
        sc != ScreenClass.phone &&
        (sc == ScreenClass.desktop ||
            MediaQuery.sizeOf(context).width > 1000)) {
      sidebar = MemberSidebar(channel: c);
    }

    final body = side && sc == ScreenClass.phone
        ? sidebar!
        : Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: main),
              ?sidebar,
            ],
          );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true):
            () => _navChannel(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true):
            () => _navChannel(-1),
        const SingleActivator(
          LogicalKeyboardKey.arrowDown,
          alt: true,
          control: true,
        ): () => _navServer(1),
        const SingleActivator(
          LogicalKeyboardKey.arrowUp,
          alt: true,
          control: true,
        ): () => _navServer(-1),
        if (side)
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              setState(() => mode = _SidebarMode.members),
      },
      child: Focus(
        autofocus: false,
        child: Column(
          children: [
            _ChannelHeader(
              channel: c,
              mode: mode,
              query: query,
              onMode: (m, {String q = ''}) => setState(() {
                mode = m;
                query = q;
              }),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

class _ChannelHeader extends StatelessWidget {
  const _ChannelHeader({
    required this.channel,
    required this.mode,
    required this.query,
    required this.onMode,
  });
  final Json channel;
  final _SidebarMode mode;
  final String query;
  final void Function(_SidebarMode, {String q}) onMode;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final settings = context.watch<SettingsStore>();
    final voice = context.watch<VoiceManager>();
    final cs = context.cs;
    final sc = screenClassOf(MediaQuery.sizeOf(context));
    final id = channel['_id'] as String;
    final type = channel['channel_type'] as String;
    final sid = channel['server'] as String?;
    final hasSidebar = type != 'SavedMessages' && type != 'DirectMessage';
    final desc = channel['description'] as String?;

    Widget icon;
    Widget title;
    Widget? subtitle;
    switch (type) {
      case 'TextChannel':
      case 'Group':
        icon = const Icon(Icons.grid_3x3);
        title = InkWell(
          onTap: () => showChannelInfo(context, channel),
          child: Text(channel['name'] as String? ?? ''),
        );
        if (sc != ScreenClass.phone && desc != null && desc.isNotEmpty) {
          subtitle = Row(
            children: [
              Container(
                height: 20,
                width: 1,
                margin: const EdgeInsets.symmetric(horizontal: 5),
                color: cs.outlineVariant,
              ),
              Expanded(
                child: Tooltip(
                  message: tr('Click to show full description'),
                  child: InkWell(
                    onTap: () => showChannelInfo(context, channel),
                    child: Text(
                      desc.split('\n').first,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ],
          );
        }
      case 'DirectMessage':
        final other = ((channel['recipients'] as List?) ?? const [])
            .cast<String>()
            .firstWhere(
              (r) => r != store.userId,
              orElse: () => store.userId ?? '',
            );
        icon = const Icon(Icons.alternate_email);
        title = Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            Flexible(
              child: Text(
                store.isDeletedUser(store.user(other))
                    ? 'Deleted User'
                    : store.user(other)?['username'] as String? ??
                          store.displayName(other),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: StatusColors.of(
                  store.user(other)?['online'] == true
                      ? ((store.user(other)?['status'] as Map?)?['presence']
                                as String? ??
                            'Online')
                      : null,
                ),
                shape: BoxShape.circle,
              ),
            ),
          ],
        );
      default:
        icon = const Icon(Icons.sticky_note_2_outlined);
        title = Text(tr('Saved Notes'));
    }

    final canSettings =
        (type == 'Group' || sid != null) &&
        store.canAny(id, [Perm.manageChannel, Perm.managePermissions]);
    final inCall = voice.showCard(channel);
    final searchOpen = mode == _SidebarMode.search;

    // Phones get a back button that returns to the server channel list (or
    // Home for DMs), mirroring the Android conversation screen.
    final Widget? leading = sc == ScreenClass.phone
        ? IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: tr('Back'),
            onPressed: () => context.canPop()
                ? context.pop()
                : context.goPath(sid != null ? '/server/$sid' : '/app'),
          )
        : null;

    return PageHeader(
      leading: leading,
      icon: icon,
      title: title,
      subtitle: subtitle,
      actions: [
        if (store.isVoice(channel) && !inCall && store.can(id, Perm.connect))
          IconButton(
            tooltip: tr('Join the voice channel'),
            icon: const Icon(Icons.call_outlined),
            onPressed: () => voice.connect(id),
          ),
        if (canSettings)
          IconButton(
            tooltip: tr('Channel Settings'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => showChannelSettings(context, id),
          ),
        if (type == 'Group')
          IconButton(
            tooltip: tr('Add friends to group'),
            icon: const Icon(Icons.person_add_outlined),
            onPressed: () => showAddMembersToGroup(context, channel),
          ),
        if (hasSidebar || type == 'DirectMessage' || type == 'SavedMessages')
          IconButton(
            tooltip: tr('View pinned messages'),
            icon: Icon(
              Icons.push_pin_outlined,
              color: mode == _SidebarMode.pins ? cs.primary : null,
            ),
            onPressed: () => onMode(
              mode == _SidebarMode.pins
                  ? _SidebarMode.members
                  : _SidebarMode.pins,
            ),
          ),
        if (hasSidebar)
          IconButton(
            tooltip: tr('View members'),
            icon: const Icon(Icons.group_outlined),
            onPressed: () {
              if (mode == _SidebarMode.members) {
                settings.toggleSectionState(_memberSidebarKey, true);
              } else {
                settings.setSectionState(_memberSidebarKey, true);
                onMode(_SidebarMode.members);
              }
            },
          ),
        if (sc == ScreenClass.desktop || mode != _SidebarMode.members)
          _SearchBox(
            query: searchOpen ? query : '',
            onChanged: (v) => v.isEmpty
                ? onMode(_SidebarMode.members)
                : onMode(_SidebarMode.search, q: v),
          )
        else
          IconButton(
            tooltip: tr('Search'),
            icon: const Icon(Icons.search),
            onPressed: () => onMode(_SidebarMode.search),
          ),
        if (settings.copyId)
          IconButton(
            icon: const Icon(Icons.tag_outlined),
            tooltip: tr('Copy ID'),
            onPressed: () => copyText(context, id),
          ),
        if (store.isAdmin)
          IconButton(
            icon: const Icon(Icons.admin_panel_settings_outlined),
            tooltip: tr('Admin Panel'),
            onPressed: () => context.goPath('/admin?s=lookup&id=$id'),
          ),
      ],
    );
  }
}

class _SearchBox extends StatefulWidget {
  const _SearchBox({required this.query, required this.onChanged});
  final String query;
  final ValueChanged<String> onChanged;
  @override
  State<_SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<_SearchBox> {
  late final _ctl = TextEditingController(text: widget.query);

  @override
  void didUpdateWidget(covariant _SearchBox old) {
    super.didUpdateWidget(old);
    if (widget.query != _ctl.text && widget.query.isEmpty) _ctl.clear();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 240,
    height: 40,
    child: TextField(
      controller: _ctl,
      onSubmitted: widget.onChanged,
      onChanged: (v) {
        if (v.isEmpty) widget.onChanged('');
      },
      decoration: InputDecoration(
        hintText: 'Search messages...',
        filled: true,
        fillColor: context.cs.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(40),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(40),
          borderSide: BorderSide.none,
        ),
      ),
    ),
  );
}

/// Mature channel confirmation + geo-restriction (`AgeGate`).
class _AgeGate extends StatefulWidget {
  const _AgeGate({
    required this.enabled,
    required this.contentId,
    required this.contentName,
    required this.child,
  });
  final bool enabled;
  final String contentId, contentName;
  final Widget child;
  @override
  State<_AgeGate> createState() => _AgeGateState();
}

class _AgeGateState extends State<_AgeGate> {
  static Future<Map<String, dynamic>>? _geo;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      _geo ??= http.get(Uri.parse('https://geo.revolt.chat')).then((r) {
        if (r.statusCode >= 400) throw Exception('Failed to fetch geo data');
        return (jsonDecode(r.body) as Map).cast<String, dynamic>();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final settings = context.watch<SettingsStore>();
    final cs = context.cs;
    final confirmed = settings.sectionState(_matureKey, false);
    final allowed = settings.sectionState('${widget.contentId}-nsfw', false);

    return FutureBuilder<Map<String, dynamic>>(
      future: _geo,
      builder: (c, snap) {
        final restricted =
            snap.connectionState != ConnectionState.done ||
            snap.hasError ||
            snap.data?['isAgeRestrictedGeo'] == true;
        Widget gate(List<Widget> children) => Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Gap.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: Gap.md,
              children: [
                const Icon(
                  Icons.warning_rounded,
                  size: 128,
                  color: Colors.orange,
                ),
                Text(
                  widget.contentName,
                  style: TextStyle(fontSize: 32, color: cs.onSurface),
                ),
                ...children,
              ],
            ),
          ),
        );
        if (snap.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator());
        if (restricted) {
          return gate([
            Text(
              snap.data?['countryCode'] == 'GB'
                  ? 'This channel is not available in your region while we review options on legal compliance.'
                  : 'This content is not available in your region.',
              textAlign: TextAlign.center,
            ),
            TextButton(
              onPressed: () =>
                  context.canPop() ? context.pop() : context.goPath('/'),
              child: Text(tr('Back')),
            ),
          ]);
        }
        if (confirmed && allowed) return widget.child;
        return gate([
          Text(tr('This channel is marked as mature.')),
          InkWell(
            onTap: () => settings.toggleSectionState(_matureKey, false),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: confirmed,
                  onChanged: (_) =>
                      settings.toggleSectionState(_matureKey, false),
                ),
                Text(tr('I confirm that I am at least 18 years old.')),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: Gap.lg,
            children: [
              TextButton(
                onPressed: () =>
                    context.canPop() ? context.pop() : context.goPath('/'),
                child: Text(tr('Back')),
              ),
              FilledButton(
                onPressed: confirmed
                    ? () => settings.setSectionState(
                        '${widget.contentId}-nsfw',
                        true,
                      )
                    : null,
                child: Text(tr('Enter Channel')),
              ),
            ],
          ),
        ]);
      },
    );
  }
}
