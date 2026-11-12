import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../api/client_store.dart';
import '../core/i18n.dart';
import '../push/push_service.dart';
import '../theme/tokens.dart';
import '../voice/voice_manager.dart';
import 'widgets.dart' show UserAvatar;

/// Full-width incoming-call card shown while a `VoiceCallUpdate` gateway
/// event is ringing — the Flutter counterpart of the Android app's
/// incoming-call screen, surfaced as an overlay so it works on every
/// platform and screen size.
///
/// This overlay lives in `MaterialApp.router`'s `builder`, above the
/// `Router` widget, so `GoRouter.of(context)` is unavailable here — the
/// router instance is passed in directly.
class IncomingCallOverlay extends StatelessWidget {
  const IncomingCallOverlay({super.key, required this.router});
  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    final push = context.watch<PushService>();
    return ValueListenableBuilder<Json?>(
      valueListenable: push.incomingCall,
      builder: (context, call, _) {
        if (call == null) return const SizedBox.shrink();
        final store = context.read<ClientStore>();
        final channelId = call['channel_id'] as String? ?? '';
        final channel = store.channels[channelId];
        final callerId = call['initiator_id'] as String?;
        final name = store.displayName(
          callerId,
          server: channel?['server'] as String?,
        );
        final cs = context.cs;

        void accept() {
          push.clearIncomingCall();
          final host = store.host;
          router.go(
            host == null
                ? '/channel/$channelId'
                : '/i/$host/channel/$channelId',
          );
          context.read<VoiceManager>().connect(channelId);
        }

        void decline() => push.clearIncomingCall();

        return Positioned(
          top: MediaQuery.paddingOf(context).top + Gap.md,
          left: 0,
          right: 0,
          child: Center(
            child: Material(
              elevation: 8,
              shadowColor: cs.shadow,
              borderRadius: br(Radius_.lg),
              color: cs.surfaceContainerHigh,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 360),
                margin: const EdgeInsets.all(Gap.md),
                padding: const EdgeInsets.all(Gap.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tr('Incoming call'),
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: Gap.md),
                    UserAvatar(userId: callerId, size: 64),
                    const SizedBox(height: Gap.sm),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: Gap.lg),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _CallButton(
                          icon: Icons.call_end,
                          color: cs.error,
                          label: tr('Decline'),
                          onTap: decline,
                        ),
                        _CallButton(
                          icon: Icons.call,
                          color: cs.primary,
                          label: tr('Accept'),
                          onTap: accept,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
          ),
        ),
        const SizedBox(height: Gap.xs),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
