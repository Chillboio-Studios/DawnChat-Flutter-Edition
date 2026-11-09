import 'package:flutter/material.dart';

import '../../api/client_store.dart';
import '../messaging/time_utils.dart';
import 'context_menu.dart';
import '../../core/i18n.dart';

Widget _radio(bool on, BuildContext context) =>
    Icon(on ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 20, color: Theme.of(context).colorScheme.onSurface);

String _levelLabel(String level) => switch (level) {
  'all' => 'All Messages',
  'mention' => 'Mentions Only',
  _ => 'None',
};

/// Mute + notification level entries shared by channel / server / DM menus (`NotificationContextMenu`).
/// [kind] is "channel" or "server".
List<MenuItem> notificationMenu(BuildContext context, ClientStore store, String kind, String id) {
  final s = store.settings;
  final muted = s.isMuted(kind, id);
  final until = s.mutedUntil(kind, id);
  final own = s.notifFor(kind, id);
  final isChannelInServer = kind == 'channel' && store.channels[id]?['server'] != null;
  final serverLevel = isChannelInServer ? (s.notifFor('server', store.channels[id]!['server'] as String) ?? 'mention') : 'all';
  final noun = kind == 'server' ? 'Server' : 'Channel';

  void mute(int? minutes) {
    s.setMute(kind, id, minutes == null ? -1 : DateTime.now().add(Duration(minutes: minutes)).millisecondsSinceEpoch);
    store.refresh();
  }

  void level(String? v) {
    s.setNotif(kind, id, v);
    store.refresh();
  }

  return [
    if (muted)
      MenuItem.button(
        'Unmute $noun',
        icon: Icons.do_not_disturb_off_outlined,
        capitalise: false,
        sublabel: until != null && until > 0 ? 'Muted until ${formatDateTime(s, DateTime.fromMillisecondsSinceEpoch(until))}' : null,
        onTap: () {
          s.setMute(kind, id, null);
          store.refresh();
        },
      )
    else
      MenuItem.sub(
        'Mute $noun',
        icon: Icons.do_not_disturb_on_outlined,
        onTap: () => mute(null),
        children: [
          for (final (minutes, label) in <(int?, String)>[
            (15, 'For 15 minutes'),
            (60, 'For 1 hour'),
            (180, 'For 3 hours'),
            (480, 'For 8 hours'),
            (1440, 'For 24 hours'),
            (null, 'Until I turn it back on'),
          ])
            MenuItem.button(label, capitalise: false, onTap: () => mute(minutes)),
        ],
      ),
    MenuItem.sub(
      tr('Notifications'),
      icon: Icons.notifications_outlined,
      children: [
        MenuItem.button(
          kind == 'server' || !isChannelInServer ? 'Default' : 'Server Default',
          sublabel: _levelLabel(serverLevel),
          trailing: Builder(builder: (c) => _radio(own == null, c)),
          onTap: () => level(null),
        ),
        MenuItem.button(tr('All Messages'), icon: Icons.notifications_active_outlined, trailing: Builder(builder: (c) => _radio(own == 'all', c)), onTap: () => level('all')),
        MenuItem.button(tr('Mentions Only'), icon: Icons.alternate_email, trailing: Builder(builder: (c) => _radio(own == 'mention', c)), onTap: () => level('mention')),
        MenuItem.button(tr('None'), icon: Icons.notifications_off_outlined, trailing: Builder(builder: (c) => _radio(own == 'none', c)), onTap: () => level('none')),
      ],
    ),
  ];
}
