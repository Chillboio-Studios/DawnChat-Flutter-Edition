import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/client_store.dart';
import '../../api/permissions.dart';
import '../../core/i18n.dart';
import '../../router.dart';
import '../../state/channel_ordering.dart';
import '../../state/settings_store.dart';
import '../../theme/tokens.dart';
import '../menus/context_menu.dart';
import '../menus/server_menus.dart' as menus;
import '../modals/server_modals.dart';
import '../net_image.dart';
import '../voice/voice_ui.dart';
import '../widgets.dart';
import 'home_page.dart' show PageHeader;
import 'sidebars.dart' show showServerActionsSheet;

/// Full-screen channel list for a server — the phone equivalent of the
/// Android app's `ServerChannelsScreen` (`main/server/{serverId}` route).
/// Shown by `ServerHome` on `ScreenClass.phone` instead of redirecting to
/// the first channel.
class ServerChannelsScreen extends StatefulWidget {
  const ServerChannelsScreen({super.key, required this.serverId});
  final String serverId;

  @override
  State<ServerChannelsScreen> createState() => _ServerChannelsScreenState();
}

class _ServerChannelsScreenState extends State<ServerChannelsScreen> {
  String get _collapseKey => 'layout.collapsedCats.${widget.serverId}';

  Set<String> _collapsed(SettingsStore s) =>
      (s.raw<List>(_collapseKey) ?? const [])
          .whereType<String>()
          .toSet();

  void _toggle(SettingsStore s, String id) {
    final list = [..._collapsed(s)];
    if (list.contains(id)) {
      list.remove(id);
    } else {
      list.add(id);
    }
    s.setRaw(_collapseKey, list);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final settings = context.watch<SettingsStore>();
    final cs = context.cs;
    final server = store.servers[widget.serverId];

    if (server == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.goPath('/app');
      });
      return const Center(child: CircularProgressIndicator());
    }

    final serverId = widget.serverId;
    final all = store.channelsOfServer(serverId);
    final categories = orderedCategories(
      (server['categories'] as List?)?.cast<dynamic>(),
      [for (final c in all) c['_id'] as String],
    );
    final collapsed = _collapsed(settings);
    final banner = store.api.fileUrl(
      'banners',
      server['banner'] as Map?,
      width: 480,
    );

    Widget channelTile(Map<String, dynamic> c) {
      final id = c['_id'] as String;
      final isVoice =
          c['channel_type'] == 'VoiceChannel' || c['voice'] != null;
      final unread = store.isUnread(id);
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: GestureDetector(
              onSecondaryTapUp: (details) => showContextMenu(
                context,
                details.globalPosition,
                menus.channelMenu(context, c),
              ),
              onLongPressStart: (details) => showContextMenu(
                context,
                details.globalPosition,
                menus.channelMenu(context, c),
              ),
              child: MenuButton(
                height: 48,
                active: unread,
                leading: Icon(
                  isVoice ? Icons.headset_mic_outlined : Icons.tag,
                  size: 20,
                ),
                title: Text(c['name'] as String? ?? 'Unnamed'),
                trailing: unread
                    ? UnreadDot(count: store.mentionCount(id))
                    : null,
                onTap: () =>
                    context.goPath('/server/$serverId/channel/$id'),
              ),
            ),
          ),
          if (isVoice) VoiceChannelPreview(channelId: id, serverId: serverId),
        ],
      );
    }

    Widget categoryHeader(OrderedCategory cat) {
      final isCollapsed = collapsed.contains(cat.id);
      return GestureDetector(
        onSecondaryTapUp: (details) => showContextMenu(
          context,
          details.globalPosition,
          menus.categoryMenu(context, serverId, cat.toMap()),
        ),
        onLongPressStart: (details) => showContextMenu(
          context,
          details.globalPosition,
          menus.categoryMenu(context, serverId, cat.toMap()),
        ),
        child: InkWell(
          onTap: () => _toggle(settings, cat.id),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.xs),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: isCollapsed ? 0 : 0.25,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: Text(
                    cat.title.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: cs.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        PageHeader(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: tr('Back'),
            onPressed: () => context.canPop()
                ? context.pop()
                : context.goPath('/app'),
          ),
          icon: const Icon(Icons.dns_outlined),
          title: Text(server['name'] as String? ?? ''),
          actions: [
            if (store.canInServer(serverId, Perm.manageChannel))
              IconButton(
                icon: const Icon(Icons.add, size: 20),
                tooltip: tr('Create'),
                onPressed: () => _createMenu(context, serverId),
              ),
            IconButton(
              icon: const Icon(Icons.more_vert),
              tooltip: tr('Server options'),
              onPressed: () => showServerActionsSheet(context, server),
            ),
          ],
        ),
        if (banner != null)
          SizedBox(
            height: 120,
            width: double.infinity,
            child: Image(
              image: netImageProvider(banner),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              for (final cat in categories) ...[
                // The 'default' bucket holds uncategorised channels — the
                // Android screen lists them without a category header.
                if (cat.id == 'default') ...[
                  for (final id in cat.channelIds)
                    if (store.channels[id] != null)
                      channelTile(store.channels[id]!),
                ] else ...[
                  categoryHeader(cat),
                  if (!collapsed.contains(cat.id))
                    for (final id in cat.channelIds)
                      if (store.channels[id] != null)
                        channelTile(store.channels[id]!),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _createMenu(BuildContext context, String serverId) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (s) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.tag),
              title: Text(tr('Create channel')),
              onTap: () => Navigator.pop(s, 'channel'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(tr('Create category')),
              onTap: () => Navigator.pop(s, 'category'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || choice == null) return;
    if (choice == 'channel') {
      await showCreateChannel(context, serverId);
    } else {
      await showCreateCategory(context, serverId);
    }
  }
}
