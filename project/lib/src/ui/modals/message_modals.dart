import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/client_store.dart';
import '../../theme/tokens.dart';
import '../messaging/message_tile.dart';
import '../widgets.dart';
import 'app_dialog.dart';
import '../../core/i18n.dart';

Future<void> deleteMessageFlow(BuildContext context, Json message, {bool quick = false}) {
  final store = context.read<ClientStore>();
  final ch = message['channel'] as String, id = message['_id'] as String;
  if (quick) return store.deleteMessage(ch, id);
  return showAppDialog<void>(
    context,
    title: tr('Delete message'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('Are you sure you want to delete this?')),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Gap.md),
          child: IgnorePointer(child: MessageTile(message: message, serverId: store.channels[ch]?['server'] as String?, isLink: MessageLink.hide)),
        ),
      ],
    ),
    actions: [
      DlgAction(tr('Cancel')),
      DlgAction(tr('Delete'), onPressed: () async {
        await store.deleteMessage(ch, id);
        return null;
      }),
    ],
  );
}

Future<void> pinMessageFlow(BuildContext context, Json message, {bool quick = false}) {
  final store = context.read<ClientStore>();
  final ch = message['channel'] as String, id = message['_id'] as String;
  final pinned = message['pinned'] == true;
  Future<void> toggle() => pinned ? store.unpinMessage(ch, id) : store.pinMessage(ch, id);
  if (quick) return toggle();
  return showAppDialog<void>(
    context,
    title: pinned ? 'Unpin message' : 'Pin message',
    content: Text(pinned ? 'Are you sure you want to unpin this message?' : 'Are you sure you want to pin this message?'),
    actions: [
      DlgAction(tr('Cancel')),
      DlgAction(pinned ? 'Unpin' : 'Pin', onPressed: () async {
        await toggle();
        return null;
      }),
    ],
  );
}

const _contentReasons = {
  'Illegal': 'Content breaks one or more laws',
  'IllegalGoods': 'Drugs or illegal goods',
  'IllegalExtortion': 'Extortion or blackmail',
  'IllegalPornography': 'Revenge or underage pornography',
  'IllegalHacking': 'Illegal hacking or cracking',
  'ExtremeViolence': 'Extreme violence, gore or animal cruelty',
  'PromotesHarm': 'Promotes harm',
  'UnsolicitedSpam': 'Unsolicited advertising or spam',
  'Raid': 'Raid or spam attack',
  'SpamAbuse': 'Spam or similar platform abuse',
  'ScamsFraud': 'Scams or fraud',
  'Malware': 'Malware or phishing',
  'Harassment': 'Harassment or cyberbullying',
  'NoneSpecified': 'Other',
};

const _userReasons = {
  'UnsolicitedSpam': 'Unsolicited advertising or spam',
  'SpamAbuse': 'Spam or similar platform abuse',
  'InappropriateProfile': "User's profile has inappropriate content",
  'Impersonation': 'Impersonation',
  'BanEvasion': 'Ban evasion',
  'Underage': 'Not of minimum age to use the platform',
  'NoneSpecified': 'Other',
};

/// [type] is Message, User or Server.
Future<void> showReportDialog(BuildContext context, {required String type, required String id, Json? message, String? contextMessageId}) {
  final store = context.read<ClientStore>();
  final reasons = type == 'User' ? _userReasons : _contentReasons;
  var category = '';
  final detail = TextEditingController();

  Widget preview() {
    switch (type) {
      case 'User':
        return Column(children: [UserAvatar(userId: id, size: 64), Text(store.displayName(id))]);
      case 'Server':
        final s = store.servers[id];
        return Column(
          children: [
            IconAvatar(url: store.api.fileUrl('icons', s?['icon'] as Map?, width: 128), name: s?['name'] as String? ?? '?', size: 64, square: false),
            Text(s?['name'] as String? ?? ''),
          ],
        );
      default:
        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: ClipRect(child: IgnorePointer(child: MessageTile(message: message!, serverId: store.channels[message['channel']]?['server'] as String?, isLink: MessageLink.hide))),
        );
    }
  }

  return showAppDialog<void>(
    context,
    title: switch (type) {
      'User' => "Tell us what's wrong with this user",
      'Server' => "Tell us what's wrong with this server",
      _ => "Tell us what's wrong with this message",
    },
    content: StatefulBuilder(
      builder: (c, set) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          preview(),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: category.isEmpty ? null : category,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('Reason for report')),
            hint: Text(tr('Please select a reason')),
            items: [for (final e in reasons.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => set(() => category = v ?? ''),
          ),
          const SizedBox(height: 12),
          TextField(controller: detail, decoration: InputDecoration(labelText: tr('Give us some detail')), minLines: 1, maxLines: 5),
        ],
      ),
    ),
    actions: [
      DlgAction(tr('Cancel')),
      DlgAction(tr('Report'), onPressed: () async {
        if (category.isEmpty || (category == 'NoneSpecified' && detail.text.trim().isEmpty)) {
          throw 'NoReasonProvided';
        }
        await store.api.post('/safety/report', {
          'content': {
            'type': type,
            'id': id,
            'report_reason': category,
            if (type == 'User' && contextMessageId != null) 'message_id': contextMessageId,
          },
          'additional_context': detail.text,
        });
        return null;
      }),
    ],
  );
}
