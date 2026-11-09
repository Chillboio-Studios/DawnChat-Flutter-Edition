import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:provider/provider.dart';

import '../../api/client_store.dart';
import '../../api/permissions.dart';
import '../../router.dart';
import '../../state/settings_store.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../voice/voice_manager.dart';
import '../menus/context_menu.dart';
import '../menus/user_menu.dart';
import '../profile/profile.dart';
import '../widgets.dart';
import '../../core/i18n.dart';

enum BtnVariant { filled, tonal, standard, error }

/// Material 3 icon button used across the call UI (`IconButton` variants of the web client).
class VBtn extends StatelessWidget {
  const VBtn({
    super.key,
    required this.icon,
    required this.onPressed,
    this.variant = BtnVariant.standard,
    this.size = 40,
    this.tooltip,
  });
  final IconData icon;
  final VoidCallback? onPressed;
  final BtnVariant variant;
  final double size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final (bg, fg) = switch (variant) {
      BtnVariant.filled => (cs.primary, cs.onPrimary),
      BtnVariant.tonal => (cs.secondaryContainer, cs.onSecondaryContainer),
      BtnVariant.error => (cs.error, cs.onError),
      BtnVariant.standard => (Colors.transparent, cs.onSurfaceVariant),
    };
    final disabled = onPressed == null;
    final b = Material(
      color: disabled ? cs.onSurface.withValues(alpha: .12) : bg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: size * .55, color: disabled ? cs.onSurface.withValues(alpha: .38) : fg),
        ),
      ),
    );
    return tooltip == null ? b : Tooltip(message: tooltip!, child: b);
  }
}

class VoiceStatefulIcons extends StatelessWidget {
  const VoiceStatefulIcons({super.key, required this.userId, this.muted = false, this.deafened = false, this.camera = false, this.screenshare = false});
  final String userId;
  final bool muted, deafened, camera, screenshare;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final byUser = context.watch<SettingsStore>().userMuted(userId);
    return Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
      if (byUser)
        Tooltip(message: tr('You muted this user.'), child: Icon(Icons.mic_off, size: 16, color: cs.error))
      else if (muted)
        const Icon(Icons.mic_off, size: 16),
      if (deafened) const Icon(Icons.headset_off, size: 16),
      if (camera) const Icon(Icons.videocam, size: 16),
      if (screenshare) const Icon(Icons.screen_share, size: 16),
    ]);
  }
}

/// Participants shown below a channel in the sidebar (`VoiceChannelPreview`).
class VoiceChannelPreview extends StatelessWidget {
  const VoiceChannelPreview({super.key, required this.channelId, this.serverId});
  final String channelId;
  final String? serverId;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final voice = context.watch<VoiceManager>();
    final cs = context.cs;
    final live = voice.channelId == channelId && voice.room != null;
    final states = store.voiceStates[channelId]?.values.toList() ?? const [];
    if (!live && states.isEmpty) return const SizedBox.shrink();

    Widget row(String userId, {required bool speaking, required bool muted, required bool deafened, required bool camera, required bool screenshare}) {
      final name = store.displayName(userId, server: serverId);
      return InkWell(
        borderRadius: br(Radius_.md),
        onTap: () => showUserProfile(context, userId, serverId: serverId),
        child: Padding(
          padding: const EdgeInsets.all(Gap.sm),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: speaking ? cs.onSurface : cs.outline),
            child: Row(spacing: Gap.md, children: [
              Container(
                decoration: speaking ? BoxDecoration(shape: BoxShape.circle, border: Border.all(color: cs.primary, width: 2)) : null,
                child: UserAvatar(userId: userId, size: 24),
              ),
              Expanded(child: Text(name, overflow: TextOverflow.ellipsis, maxLines: 1)),
              VoiceStatefulIcons(userId: userId, muted: muted, deafened: deafened, camera: camera, screenshare: screenshare),
            ]),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: Gap.sm, bottom: Gap.sm, left: Gap.xl, right: Gap.md),
      child: Column(children: [
        if (live)
          for (final p in voice.participants)
            row(p.identity,
                speaking: voice.speaking.contains(p.identity),
                muted: p.isMuted,
                deafened: false,
                camera: p.isCameraEnabled(),
                screenshare: p.isScreenShareEnabled())
        else
          for (final s in states)
            row(s['id'] as String,
                speaking: false,
                muted: s['is_publishing'] == false,
                deafened: s['is_receiving'] == false,
                camera: s['camera'] == true,
                screenshare: s['screensharing'] == true),
      ]),
    );
  }
}

// ---------------- Call card ----------------

class VoiceCallCardStatus extends StatelessWidget {
  const VoiceCallCardStatus({super.key, this.pip = false});
  final bool pip;

  @override
  Widget build(BuildContext context) {
    final v = context.watch<VoiceManager>();
    final cs = context.cs;
    final connected = v.state == VoiceState.connected;
    final color = connected ? cs.primary : cs.outline;
    final (icon, text) = switch (v.state) {
      VoiceState.connected => (Icons.wifi_tethering, 'Connected'),
      VoiceState.connecting => (Icons.wifi_tethering, 'Connecting'),
      VoiceState.disconnected => (Icons.wifi_tethering_error, 'Disconnected'),
      VoiceState.reconnecting => (Icons.wifi_tethering, 'Reconnecting'),
      VoiceState.ready => (Icons.wifi_tethering, ''),
    };
    return TweenAnimationBuilder<double>(
      key: ValueKey(v.state),
      tween: Tween(begin: 1, end: connected ? 0 : 1),
      duration: const Duration(milliseconds: 300),
      curve: const Interval(0, 1),
      builder: (c, t, _) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color),
        if (t > 0.05 || !connected) Padding(padding: const EdgeInsets.only(left: Gap.md), child: Opacity(opacity: connected ? t : 1, child: Text(text, style: TextStyle(color: color)))),
      ]),
    );
  }
}

Future<void> toggleScreenshareUi(BuildContext context, VoiceManager voice) async {
  final settings = context.read<SettingsStore>();
  if (voice.screenshare) return voice.stopScreenshare();
  String? sourceId;
  final desktop = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS);
  if (desktop) {
    final source = await showDialog<dynamic>(context: context, builder: (_) => lk.ScreenSelectDialog());
    if (source == null) return;
    sourceId = source.id as String?;
  }
  var quality = settings.screenShareQuality;
  var audio = settings.screenShareAudio;
  if (settings.screenShareQualityAsk && context.mounted) {
    final res = await showDialog<(String, bool)>(
      context: context,
      builder: (c) => _ScreenShareSettingsDialog(quality: quality, audio: audio),
    );
    if (res == null) return;
    quality = res.$1;
    audio = res.$2;
  }
  await voice.startScreenshare(sourceId: sourceId, quality: quality, audio: audio);
}

class _ScreenShareSettingsDialog extends StatefulWidget {
  const _ScreenShareSettingsDialog({required this.quality, required this.audio});
  final String quality;
  final bool audio;
  @override
  State<_ScreenShareSettingsDialog> createState() => _ScreenShareSettingsDialogState();
}

class _ScreenShareSettingsDialogState extends State<_ScreenShareSettingsDialog> {
  late String q = widget.quality;
  late bool a = widget.audio;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(tr('Screen Share Settings')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          RadioGroup<String>(
            groupValue: q,
            onChanged: (v) => setState(() => q = v ?? q),
            child: const Column(children: [
              RadioListTile<String>(value: 'low', title: Text('720p at 30fps')),
              RadioListTile<String>(value: 'high', title: Text('1080p at 30fps')),
              RadioListTile<String>(value: 'text', title: Text('Source resolution at 5fps (text)')),
            ]),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: a,
            onChanged: (v) => setState(() => a = v ?? a),
            title: Text(tr('Share audio')),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, (q, a)), child: const Text('Share')),
        ],
      );
}

class VoiceActions extends StatelessWidget {
  const VoiceActions({super.key, this.xs = false});
  final bool xs;

  @override
  Widget build(BuildContext context) {
    final v = context.watch<VoiceManager>();
    final store = context.watch<ClientStore>();
    final cs = context.cs;
    final size = xs ? 32.0 : 40.0;
    final video = store.api.config?.video ?? true;
    final speak = v.speakingPermission;
    final listen = v.listenPermission;
    final phone = MediaQuery.sizeOf(context).width <= 640;

    final buttons = <Widget>[
      if (xs)
        VBtn(
          size: size,
          icon: Icons.north_west,
          tooltip: tr('Return to voice channel'),
          onPressed: () {
            final c = store.channels[v.channelId];
            final sid = c?['server'];
            context.goPath(sid == null ? '/channel/${v.channelId}' : '/server/$sid/channel/${v.channelId}');
          },
        ),
      if (!xs && v.layout == VoiceLayout.collapsed)
        VBtn(size: size, icon: Icons.unfold_more, tooltip: tr('Restore call window'), onPressed: () => v.toggleLayout(VoiceLayout.collapsed)),
      VBtn(
        size: size,
        variant: v.microphone ? BtnVariant.filled : BtnVariant.tonal,
        icon: v.microphone ? Icons.mic : Icons.mic_off,
        tooltip: speak ? (v.microphone ? 'Mute' : 'Unmute') : 'Missing permission',
        onPressed: speak ? v.toggleMute : null,
      ),
      VBtn(
        size: size,
        variant: v.deafened || !listen ? BtnVariant.tonal : BtnVariant.filled,
        icon: v.deafened || !listen ? Icons.headset_off : Icons.headset,
        tooltip: listen ? (v.deafened ? 'Undeafen' : 'Deafen') : 'Missing permission',
        onPressed: listen ? v.toggleDeafen : null,
      ),
      VBtn(
        size: size,
        variant: video && v.video ? BtnVariant.filled : BtnVariant.tonal,
        icon: Icons.videocam,
        tooltip: video ? (v.video ? 'Stop camera' : 'Start camera') : 'Coming soon! 👀',
        onPressed: video ? v.toggleCamera : null,
      ),
      if (video && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) && !kIsWeb)
        VBtn(size: size, icon: Icons.flip_camera_android, tooltip: 'Switch camera', onPressed: v.switchCamera),
      VBtn(
        size: size,
        variant: video && v.screenshare ? BtnVariant.filled : BtnVariant.tonal,
        icon: v.screenshare ? Icons.stop_screen_share : Icons.screen_share,
        tooltip: video ? (v.screenshare ? 'Stop sharing' : 'Share screen') : 'Coming soon! 👀',
        onPressed: video && (v.screenShareSupported || v.screenshare) ? () => toggleScreenshareUi(context, v) : null,
      ),
      VBtn(size: size, variant: BtnVariant.error, icon: Icons.call_end, tooltip: tr('End call'), onPressed: v.disconnect),
    ];

    final row = Row(mainAxisSize: MainAxisSize.min, spacing: phone ? Gap.sm : Gap.md, children: buttons);
    return Container(
      padding: EdgeInsets.all(phone ? Gap.xs : Gap.md),
      decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(999)),
      child: phone ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: row) : row,
    );
  }
}

class _LayoutButtons extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final v = context.watch<VoiceManager>();
    final desktop = screenClassOf(MediaQuery.sizeOf(context)) == ScreenClass.desktop;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (desktop) ...[
        VBtn(icon: Icons.unfold_less, tooltip: tr('Collapse call window'), onPressed: () => v.toggleLayout(VoiceLayout.collapsed)),
        VBtn(
          icon: v.layout == VoiceLayout.expanded ? Icons.close_fullscreen : Icons.open_in_full,
          tooltip: v.layout == VoiceLayout.expanded ? 'Restore call window' : 'Maximize call window',
          onPressed: () => v.toggleLayout(VoiceLayout.expanded),
        ),
      ],
      VBtn(
        icon: v.layout == VoiceLayout.fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
        onPressed: () => v.toggleLayout(VoiceLayout.fullscreen),
      ),
    ]);
  }
}

/// Preview card shown while not in a call (`VoiceCallCardPreview`).
class VoiceCallPreviewCard extends StatelessWidget {
  const VoiceCallPreviewCard({super.key, required this.channel});
  final Map<String, dynamic> channel;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final voice = context.watch<VoiceManager>();
    final cs = context.cs;
    final id = channel['_id'] as String;
    final ids = (store.voiceStates[id]?.keys ?? const <String>[]).toList();
    final names = [for (final u in ids) store.user(u)?['username'] as String?].whereType<String>().toList();
    final sub = names.length > 3
        ? 'with ${names.length} others'
        : names.isNotEmpty
            ? 'with ${names.join(', ')}'
            : 'Start the call';
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        height: 120,
        margin: const EdgeInsets.all(Gap.md),
        decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: br(Radius_.lg)),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: br(Radius_.lg),
          child: InkWell(
            borderRadius: br(Radius_.lg),
            onTap: store.can(id, Perm.connect) ? () => voice.connect(id) : null,
            child: Padding(
              padding: const EdgeInsets.all(Gap.lg),
              child: DefaultTextStyle.merge(
                style: TextStyle(color: cs.onSecondaryContainer),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, spacing: Gap.sm, children: [
                  SizedBox(
                    height: 24,
                    child: ids.isEmpty
                        ? const Icon(Icons.voice_chat, size: 24)
                        : Stack(children: [
                            for (var i = 0; i < ids.length; i++) Positioned(left: i * 15.0, child: UserAvatar(userId: ids[i], size: 24)),
                          ]),
                  ),
                  Text(voice.state == VoiceState.ready ? 'Join the voice channel' : 'Switch to this voice channel',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------- Participant tile ----------------

class ParticipantTileWidget extends StatefulWidget {
  const ParticipantTileWidget({super.key, required this.tile, this.compact = false});
  final VoiceTile tile;
  final bool compact;

  @override
  State<ParticipantTileWidget> createState() => _ParticipantTileWidgetState();
}

class _ParticipantTileWidgetState extends State<ParticipantTileWidget> {
  @override
  void initState() {
    super.initState();
    final pub = widget.tile.publication;
    if (pub is lk.RemoteTrackPublication && !pub.subscribed) pub.subscribe();
  }

  @override
  Widget build(BuildContext context) {
    final v = context.watch<VoiceManager>();
    final store = context.watch<ClientStore>();
    final settings = context.watch<SettingsStore>();
    final cs = context.cs;
    final t = widget.tile;
    final p = t.participant;
    final isScreen = t.isScreenshare;
    final focused = v.isFocus(t);
    final hasVideo = t.hasVideo;
    final speaking = !isScreen && v.speaking.contains(p.identity);
    final name = store.displayName(p.identity);
    final screenAudioMuted = isScreen && settings.screenShareMuted(p.identity);

    if (isScreen && (t.publication?.muted ?? true)) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () {
        if (!hasVideo && !isScreen) return;
        v.toggleFocus(t);
      },
      onLongPressStart: (d) => showUserVoiceMenu(context, p.identity, d.globalPosition, screenshare: isScreen),
      onSecondaryTapUp: (d) => showUserVoiceMenu(context, p.identity, d.globalPosition, screenshare: isScreen),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: const Color(0x22000000),
          borderRadius: br(Radius_.lg),
          border: Border.all(color: speaking ? cs.primary : Colors.transparent, width: 3),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(fit: StackFit.expand, children: [
          if (hasVideo)
            lk.VideoTrackRenderer(t.publication!.track as lk.VideoTrack, fit: lk.VideoViewFit.contain)
          else
            Center(child: UserAvatar(userId: p.identity, size: widget.compact ? 32 : 48)),
          Positioned(
            left: Gap.lg,
            right: Gap.lg,
            bottom: Gap.md,
            child: Opacity(
              opacity: 1,
              child: DefaultTextStyle.merge(
                style: TextStyle(color: cs.onSurface, shadows: hasVideo ? const [Shadow(blurRadius: 4)] : null),
                child: Row(children: [
                  Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (isScreen)
                    (screenAudioMuted || (t.participant.audioTrackPublications.where((x) => x.source == lk.TrackSource.screenShareAudio).isEmpty))
                        ? Icon(Icons.volume_off, size: 18, color: screenAudioMuted ? cs.error : null)
                        : const SizedBox.shrink()
                  else
                    VoiceStatefulIcons(userId: p.identity, muted: p.isMuted, camera: p.isCameraEnabled()),
                ]),
              ),
            ),
          ),
          if (focused)
            Positioned(top: 4, right: 4, child: Icon(Icons.push_pin, size: 16, color: cs.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

Future<void> showUserVoiceMenu(BuildContext context, String userId, Offset position, {bool screenshare = false}) {
  final store = context.read<ClientStore>();
  final channelId = context.read<VoiceManager>().channelId;
  final channel = channelId == null ? null : store.channels[channelId];
  return showContextMenu(
    context,
    position,
    userMenu(context, userId, channel: channel, inVoice: true, isScreenshare: screenshare),
  );
}

// ---------------- Active room ----------------

class VoiceActiveRoom extends StatelessWidget {
  const VoiceActiveRoom({super.key});

  @override
  Widget build(BuildContext context) {
    final v = context.watch<VoiceManager>();
    final collapsed = v.layout == VoiceLayout.collapsed;
    final fullscreen = v.layout == VoiceLayout.fullscreen;
    final phone = MediaQuery.sizeOf(context).width <= 640;

    return Padding(
      padding: collapsed
          ? EdgeInsets.zero
          : fullscreen
              ? const EdgeInsets.all(Gap.sm)
              : const EdgeInsets.all(Gap.md),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, spacing: Gap.md, children: [
        if (!collapsed) const Expanded(child: _Participants()),
        if (phone)
          Column(children: [
            Row(children: [
              Expanded(child: Opacity(opacity: collapsed ? 0 : 1, child: const VoiceCallCardStatus())),
              Opacity(opacity: collapsed ? 0 : 1, child: _LayoutButtons()),
            ]),
            const VoiceActions(),
          ])
        else
          Row(children: [
            Expanded(child: Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.all(Gap.md), child: Opacity(opacity: collapsed ? 0 : 1, child: const VoiceCallCardStatus())))),
            const VoiceActions(),
            Expanded(child: Align(alignment: Alignment.centerRight, child: Padding(padding: const EdgeInsets.all(Gap.md), child: _LayoutButtons()))),
          ]),
      ]),
    );
  }
}

class _Participants extends StatelessWidget {
  const _Participants();

  @override
  Widget build(BuildContext context) {
    final v = context.watch<VoiceManager>();
    final tiles = v.tiles;
    final focus = v.focusTile;
    final fullscreen = v.layout == VoiceLayout.fullscreen;

    return LayoutBuilder(builder: (context, box) {
      if (focus != null) {
        final others = tiles.where((t) => t.id != focus.id).toList();
        final stripH = box.maxHeight.isFinite ? (box.maxHeight * .18).clamp(96.0, 180.0) : 120.0;
        return Stack(children: [
          Column(spacing: Gap.sm, children: [
            Expanded(child: ParticipantTileWidget(key: ValueKey(focus.id), tile: focus)),
            if (v.showBar)
              SizedBox(
                height: stripH,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final t in others)
                    Padding(
                      padding: const EdgeInsets.only(right: Gap.sm),
                      child: AspectRatio(aspectRatio: 16 / 9, child: ParticipantTileWidget(key: ValueKey(t.id), tile: t, compact: true)),
                    ),
                ]),
              ),
          ]),
          Positioned(
            top: Gap.xs,
            left: 0,
            right: 0,
            child: Center(
              child: VBtn(
                size: 32,
                variant: BtnVariant.tonal,
                icon: v.showBar ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                tooltip: v.showBar ? 'Hide Others' : 'Show Others',
                onPressed: v.toggleShowBar,
              ),
            ),
          ),
        ]);
      }

      final w = box.maxWidth;
      final phone = MediaQuery.sizeOf(context).width <= 640;
      final minW = phone ? min(MediaQuery.sizeOf(context).width * .42, 180.0) : 250.0;
      final count = max(1, tiles.length);
      var tileW = max(minW, w / count - Gap.md);
      if (fullscreen) tileW = min(w, max(minW, w / min(count, 3) - Gap.lg));
      tileW = min(tileW, w);
      return SingleChildScrollView(
        child: Center(
          child: Wrap(alignment: WrapAlignment.center, spacing: Gap.md, runSpacing: Gap.md, children: [
            for (final t in tiles)
              SizedBox(width: tileW, child: AspectRatio(aspectRatio: 16 / 9, child: ParticipantTileWidget(key: ValueKey(t.id), tile: t))),
          ]),
        ),
      );
    });
  }
}

/// Call card placed at the top of a channel page, mirroring `VoiceChannelCallCardMount`.
class VoiceCallCardSlot extends StatelessWidget {
  const VoiceCallCardSlot({super.key, required this.channel});
  final Map<String, dynamic> channel;

  @override
  Widget build(BuildContext context) {
    final v = context.watch<VoiceManager>();
    final cs = context.cs;
    final id = channel['_id'] as String;
    if (!v.showCard(channel)) return const SizedBox.shrink();

    if (!(v.inCall && v.channelId == id)) {
      return VoiceCallPreviewCard(channel: channel);
    }
    if (v.layout == VoiceLayout.fullscreen) {
      return const SizedBox.shrink();
    }
    final h = MediaQuery.sizeOf(context).height;
    final height = v.layout == VoiceLayout.collapsed ? 56.0 : (h * .4);
    return Padding(
      padding: const EdgeInsets.all(Gap.md),
      child: SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(color: v.layout == VoiceLayout.collapsed ? Colors.transparent : cs.secondaryContainer, borderRadius: br(Radius_.lg)),
          child: const VoiceActiveRoom(),
        ),
      ),
    );
  }
}

// ---------------- PiP + fullscreen overlay ----------------

class VoiceOverlay extends StatefulWidget {
  const VoiceOverlay({super.key, required this.currentChannelId, required this.child});
  final String? currentChannelId;
  final Widget child;

  @override
  State<VoiceOverlay> createState() => _VoiceOverlayState();
}

class _VoiceOverlayState extends State<VoiceOverlay> {
  Alignment _corner = Alignment.topRight;
  Offset? _drag;

  @override
  Widget build(BuildContext context) {
    final v = context.watch<VoiceManager>();
    final cs = context.cs;
    final size = MediaQuery.sizeOf(context);
    final showPip = v.inCall && v.layout != VoiceLayout.fullscreen && widget.currentChannelId != v.channelId;
    final w = min(300.0, size.width - 24);
    const h = 170.0;

    return Stack(children: [
      widget.child,
      if (v.inCall && v.layout == VoiceLayout.fullscreen)
        Positioned.fill(
          child: Material(
            color: cs.secondaryContainer,
            child: const SafeArea(child: VoiceActiveRoom()),
          ),
        ),
      if (showPip)
        AnimatedAlign(
          duration: _drag == null ? const Duration(milliseconds: 200) : Duration.zero,
          curve: Curves.easeOutBack,
          alignment: _corner,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 72, 16, 72),
            child: GestureDetector(
              onPanUpdate: (d) => setState(() {
                _drag = (_drag ?? Offset.zero) + d.delta;
                final x = (_corner.x + d.delta.dx / (size.width / 2)).clamp(-1.0, 1.0);
                final y = (_corner.y + d.delta.dy / (size.height / 2)).clamp(-1.0, 1.0);
                _corner = Alignment(x, y);
              }),
              onPanEnd: (_) => setState(() {
                _corner = Alignment(_corner.x < 0 ? -1 : 1, _corner.y < 0 ? -1 : 1);
                _drag = null;
              }),
              child: SizedBox(width: w, height: h, child: const _PipCard()),
            ),
          ),
        ),
    ]);
  }
}

class _PipCard extends StatelessWidget {
  const _PipCard();

  @override
  Widget build(BuildContext context) {
    final v = context.watch<VoiceManager>();
    final cs = context.cs;
    final focus = v.focusTile;
    final store = context.watch<ClientStore>();
    return Material(
      color: cs.secondaryContainer,
      borderRadius: br(Radius_.lg),
      elevation: 6,
      clipBehavior: Clip.antiAlias,
      child: Stack(fit: StackFit.expand, children: [
        if (focus != null && focus.hasVideo)
          lk.VideoTrackRenderer(focus.publication!.track as lk.VideoTrack, fit: lk.VideoViewFit.cover)
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 56, top: 28),
            child: Center(
              child: Wrap(alignment: WrapAlignment.center, spacing: 4, runSpacing: 4, children: [
                for (final p in v.participants)
                  Container(
                    decoration: v.speaking.contains(p.identity) ? BoxDecoration(shape: BoxShape.circle, border: Border.all(color: cs.primary, width: 2)) : null,
                    child: Stack(alignment: Alignment.center, children: [
                      UserAvatar(userId: p.identity, size: 24),
                      if (p.isMuted) const Icon(Icons.mic_off, size: 14, color: Colors.white70),
                    ]),
                  ),
              ]),
            ),
          ),
        const Positioned(left: Gap.md, top: Gap.md, child: VoiceCallCardStatus(pip: true)),
        Positioned(
          left: 0,
          right: 0,
          bottom: Gap.md,
          child: Center(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: FittedBox(child: VoiceActions(xs: true)))),
        ),
        if (store.channels[v.channelId] == null) const SizedBox.shrink(),
      ]),
    );
  }
}
