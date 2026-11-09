import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../api/client_store.dart';
import '../../api/permissions.dart';
import '../../core/links.dart';
import '../../router.dart';
import '../../state/draft_store.dart';
import '../../state/settings_store.dart';
import '../messaging/emoji_picker.dart';
import '../messaging/embeds.dart';
import '../messaging/markdown_view.dart';
import '../modals/message_modals.dart';
import '../widgets.dart';
import 'context_menu.dart';
import '../../core/i18n.dart';

/// Converts a picker result (":ID:" for custom, raw unicode otherwise) into a reaction key.
String reactionKey(String picked) => picked.startsWith(':') && picked.endsWith(':') ? picked.substring(1, picked.length - 1) : picked;

Future<void> reactToMessage(BuildContext context, Json message) async {
  final store = context.read<ClientStore>();
  final e = await pickEmoji(context, serverId: store.channels[message['channel']]?['server'] as String?);
  if (e == null || !context.mounted) return;
  try {
    await store.react(message['channel'] as String, message['_id'] as String, reactionKey(e), true);
  } catch (err) {
    if (context.mounted) showSnack(context, errorText(err));
  }
}

List<MenuItem> messageMenu(BuildContext context, Json message, {Map? file, String? link}) {
  final store = context.read<ClientStore>();
  final settings = context.read<SettingsStore>();
  final channelId = message['channel'] as String;
  final channel = store.channels[channelId];
  final self = message['author'] == store.userId;
  final isDm = channel?['channel_type'] == 'DirectMessage';
  final canSend = store.can(channelId, Perm.sendMessage);
  final canReact = store.can(channelId, Perm.react);
  final canManage = store.can(channelId, Perm.manageMessages);
  final isSystem = message['system'] != null;
  final reactions = (message['reactions'] as Map?)?.keys.cast<String>().toList() ?? const <String>[];
  final urls = ApiClientUrls.of(context);
  final serverId = channel?['server'] as String?;
  final id = message['_id'] as String;

  return [
    if (file != null) ...[
      MenuItem.button(tr('Open file'), icon: Icons.open_in_new, onTap: () => openUrl(urls.previewUrl(file))),
      MenuItem.button(tr('Copy file link'), icon: Icons.link, onTap: () => copyText(context, urls.previewUrl(file))),
      MenuItem.button(tr('Save file'), icon: Icons.download, onTap: () => openUrl(urls.originalUrl(file))),
      const MenuItem.divider(),
    ],
    if (link != null) ...[
      MenuItem.button(tr('Copy link'), icon: Icons.link, onTap: () => copyText(context, link)),
      const MenuItem.divider(),
    ],
    if (canSend)
      MenuItem.button(tr('Reply'), icon: Icons.reply, onTap: () => context.read<DraftStore>().addReply(message, store.userId!)),
    MenuItem.button(tr('Mark as unread'), icon: Icons.mark_chat_unread_outlined, onTap: () => store.markUnreadFrom(channelId, id)),
    MenuItem.button(tr('Copy text'), icon: Icons.content_copy, onTap: () => copyText(context, message['content'] as String? ?? '')),
    const MenuItem.divider(),
    if (canReact) MenuItem.button(tr('React'), icon: Icons.emoji_emotions_outlined, onTap: () => reactToMessage(context, message)),
    if (self && canSend)
      MenuItem.button(tr('Edit message'), icon: Icons.edit_outlined, onTap: () => context.read<DraftStore>().setEditing(channelId, id)),
    if (isDm || canManage)
      MenuItem.button(
        message['pinned'] == true ? 'Unpin message' : 'Pin message',
        icon: Icons.push_pin_outlined,
        onTap: () => pinMessageFlow(context, message, quick: HardwareKeyboard.instance.isShiftPressed),
      ),
    if (reactions.isNotEmpty && canManage) ...[
      MenuItem.sub(
        tr('Remove reaction'),
        icon: Icons.delete_sweep_outlined,
        destructive: true,
        children: [
          for (final k in reactions)
            MenuItem.custom(
              InkWell(
                onTap: () {
                  Navigator.of(context, rootNavigator: true).pop();
                  store.removeReactionForAll(channelId, id, k);
                },
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8), child: Align(alignment: Alignment.centerLeft, child: EmojiView(k, size: 20))),
              ),
            ),
        ],
      ),
      MenuItem.button(tr('Remove all reactions'), icon: Icons.sentiment_dissatisfied_outlined, destructive: true, onTap: () => store.clearReactions(channelId, id)),
    ],
    if (self || canManage)
      MenuItem.button(
        tr('Delete message'),
        icon: Icons.delete_outline,
        destructive: true,
        onTap: () => deleteMessageFlow(context, message, quick: HardwareKeyboard.instance.isShiftPressed),
      ),
    if (!self && !isSystem)
      MenuItem.button(tr('Report message'), icon: Icons.report_outlined, destructive: true, onTap: () => showReportDialog(context, type: 'Message', id: id, message: message)),
    const MenuItem.divider(),
    if (settings.adminPanel)
      MenuItem.button(tr('Admin Panel'), icon: Icons.shield_outlined, onTap: () => openUrl(adminInspectUrl('message', id))),
    MenuItem.button(
      tr('Copy message link'),
      icon: Icons.share_outlined,
      onTap: () => copyText(context, context.fullHref('${serverId != null ? '/server/$serverId' : ''}/channel/$channelId/$id')),
    ),
    if (settings.copyId) MenuItem.button(tr('Copy message ID'), icon: Icons.badge_outlined, onTap: () => copyText(context, id)),
  ];
}
