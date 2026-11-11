import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:flutter_background/flutter_background.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:media_kit/media_kit.dart' as mk;

import '../api/client_store.dart';
import '../api/permissions.dart';
import '../api/transport.dart';
import '../state/settings_store.dart';

/// Plays the client sounds from assets/sounds.
class SoundService {
  SoundService(this.settings);
  final SettingsStore settings;
  mk.Player? _playerInstance;
  mk.Player get _player => _playerInstance ??= mk.Player();

  static const _files = {
    'deafen': 'deafen.ogg',
    'message': 'message_sound.ogg',
    'mute': 'mute.ogg',
    'ringtoneIncoming': 'ringtone_incoming.ogg',
    'ringtoneOutgoing': 'ringtone_outgoing.ogg',
    'streamEnd': 'stream_end.ogg',
    'streamStart': 'stream_start.ogg',
    'streamViewerJoin': 'stream_viewer_join.ogg',
    'streamViewerLeave': 'stream_viewer_leave.ogg',
    'undeafen': 'undeafen.ogg',
    'unmute': 'unmute.ogg',
    'userJoinVoice': 'user_join_voice.ogg',
    'userLeaveVoice': 'user_leave_voice.ogg',
    'userMoved': 'user_moved.ogg',
  };

  Future<void> play(String key, {bool force = false}) async {
    if (!force && !settings.soundEnabled(key)) return;
    final file = _files[key];
    if (file == null) return;
    try {
      await _player.stop();
      await _player.open(mk.Media('asset:///assets/sounds/$file'));
    } catch (_) {}
  }
}

enum VoiceState { ready, connecting, connected, disconnected, reconnecting }

enum VoiceLayout { collapsed, expanded, fullscreen }

/// A camera or screenshare tile in the call.
class VoiceTile {
  VoiceTile(this.participant, this.source, this.publication);
  final Participant participant;
  final TrackSource source;
  final TrackPublication? publication;
  bool get isScreenshare => source == TrackSource.screenShareVideo;
  String get id => '${source.name}_${participant.sid}';
  bool get hasVideo =>
      publication != null &&
      !publication!.muted &&
      publication!.track is VideoTrack;
}

/// LiveKit voice/video session; behaviour follows the web client's `rtc/state.tsx`.
class VoiceManager extends ChangeNotifier {
  VoiceManager(this.store, this.settings, this.sounds) {
    settings.addListener(_applySettings);
  }

  final ClientStore store;
  final SettingsStore settings;
  final SoundService sounds;

  Room? room;
  EventsListener<RoomEvent>? _listener;
  String? channelId;
  VoiceState state = VoiceState.ready;
  VoiceLayout? layout;
  String? focusId;
  bool showBar = true;
  final Set<String> speaking = {};
  final ValueNotifier<String?> lastError = ValueNotifier(null);
  final Set<String> _screenShareTracks = {};

  bool get inCall => channelId != null && state != VoiceState.ready;
  bool get connected => state == VoiceState.connected;
  bool get connecting => state == VoiceState.connecting;
  bool get microphone => settings.micOn && !settings.deafen;
  bool get deafened => settings.deafen;
  bool get video => room?.localParticipant?.isCameraEnabled() ?? false;
  bool get screenshare =>
      room?.localParticipant?.isScreenShareEnabled() ?? false;
  bool get screenShareSupported =>
      !(kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS));
  String? get error => lastError.value;

  bool get speakingPermission =>
      channelId != null && store.can(channelId!, Perm.speak);
  bool get listenPermission =>
      channelId != null && store.can(channelId!, Perm.listen);

  List<Participant> get participants => [
    if (room?.localParticipant != null) room!.localParticipant!,
    ...?room?.remoteParticipants.values,
  ];

  /// Camera tiles (with placeholders) plus any screenshare tiles, like `useTracks` on web.
  List<VoiceTile> get tiles {
    final out = <VoiceTile>[];
    for (final p in participants) {
      TrackPublication? cam;
      for (final pub in p.videoTrackPublications) {
        if (pub.source == TrackSource.camera) cam = pub;
      }
      out.add(VoiceTile(p, TrackSource.camera, cam));
      for (final pub in p.videoTrackPublications) {
        if (pub.source == TrackSource.screenShareVideo) {
          out.add(VoiceTile(p, TrackSource.screenShareVideo, pub));
        }
      }
    }
    return out;
  }

  VoiceTile? get focusTile {
    final id = focusId;
    if (id == null) return null;
    for (final t in tiles) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Whether the call card should be shown for a channel.
  bool showCard(Map<String, dynamic> channel) {
    final id = channel['_id'] as String;
    return store.isVoice(channel) &&
        (channelId == id ||
            channel['channel_type'] == 'TextChannel' ||
            (store.voiceStates[id]?.isNotEmpty ?? false));
  }

  Future<String?> _probeNode() async {
    final nodes =
        ((store.api.config?.features['livekit'] as Map?)?['nodes'] as List?) ??
        const [];
    if (nodes.isEmpty) return null;
    final completer = Completer<String?>();
    var pending = nodes.length;
    for (final n in nodes) {
      final node = n as Map;
      sendRequest(
            'GET',
            (node['public_url'] as String).replaceFirst('wss', 'https'),
          )
          .then((_) {
            if (!completer.isCompleted)
              completer.complete(node['name'] as String?);
          })
          .catchError((_) {
            if (--pending == 0 && !completer.isCompleted)
              completer.complete(null);
            return null;
          });
    }
    return completer.future.timeout(
      const Duration(seconds: 4),
      onTimeout: () => null,
    );
  }

  Future<void> connect(String channel) async {
    await disconnect(playSound: false);
    channelId = channel;
    state = VoiceState.connecting;
    lastError.value = null;
    notifyListeners();
    try {
      final node = await _probeNode();
      final auth = await store.joinCall(channel, node: node);
      final r = Room(
        roomOptions: RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultAudioCaptureOptions: AudioCaptureOptions(
            deviceId: settings.audioInput,
            echoCancellation: settings.echoCancellation,
            noiseSuppression: settings.noiseSuppression != 'disabled',
            autoGainControl: settings.autoGainControl,
          ),
          defaultCameraCaptureOptions: CameraCaptureOptions(
            deviceId: settings.videoInput,
            params: VideoParametersPresets.h720_169,
          ),
          defaultVideoPublishOptions: const VideoPublishOptions(
            videoEncoding: VideoEncoding(maxBitrate: 1700000, maxFramerate: 30),
          ),
        ),
      );
      room = r;
      r.addListener(_onRoomChanged);
      _listener = r.createListener()
        ..on<ActiveSpeakersChangedEvent>((e) {
          speaking
            ..clear()
            ..addAll(e.speakers.map((s) => s.identity));
          notifyListeners();
        })
        ..on<ParticipantConnectedEvent>((_) => sounds.play('userJoinVoice'))
        ..on<ParticipantDisconnectedEvent>((_) => sounds.play('userLeaveVoice'))
        ..on<TrackPublishedEvent>((e) {
          final pub = e.publication;
          if (pub.kind == TrackType.AUDIO) {
            if (!settings.deafen) pub.subscribe();
          } else if (pub.source == TrackSource.screenShareVideo) {
            pub.subscribe();
          }
        })
        ..on<TrackSubscribedEvent>((e) {
          if (e.publication.source == TrackSource.screenShareVideo) {
            _screenShareTracks.add(e.publication.sid);
            sounds.play('streamStart');
          }
          _applyVolumes();
        })
        ..on<TrackUnpublishedEvent>((e) {
          if (_screenShareTracks.remove(e.publication.sid))
            sounds.play('streamEnd');
        })
        ..on<RoomReconnectingEvent>((_) {
          state = VoiceState.reconnecting;
          notifyListeners();
        })
        ..on<RoomReconnectedEvent>((_) {
          state = VoiceState.connected;
          notifyListeners();
        })
        ..on<RoomDisconnectedEvent>((_) {
          if (room == r) {
            state = VoiceState.disconnected;
            notifyListeners();
          }
        });
      await r.connect(
        auth.url,
        auth.token,
        connectOptions: const ConnectOptions(autoSubscribe: false),
      );
      state = VoiceState.connected;
      for (final p in r.remoteParticipants.values) {
        for (final pub in p.trackPublications.values) {
          if (pub.kind == TrackType.AUDIO && !settings.deafen) pub.subscribe();
          if (pub.source == TrackSource.screenShareVideo)
            _screenShareTracks.add(pub.sid);
        }
      }
      if (settings.audioOutput != null) {
        final outs = await Hardware.instance.audioOutputs();
        final match = outs.where((d) => d.deviceId == settings.audioOutput);
        if (match.isNotEmpty)
          await Hardware.instance.selectAudioOutput(match.first);
      }
      if (speakingPermission) {
        try {
          final pub = await r.localParticipant?.setMicrophoneEnabled(
            settings.micOn && !settings.deafen,
          );
          settings.micOn = pub != null || !settings.micOn
              ? settings.micOn && pub != null
              : false;
        } catch (e) {
          settings.micOn = false;
        }
      }
      sounds.play('userJoinVoice');
    } catch (e) {
      _report(e);
      await disconnect(playSound: false);
    } finally {
      notifyListeners();
    }
  }

  Future<void> disconnect({bool playSound = true}) async {
    final r = room;
    final was = inCall;
    room = null;
    channelId = null;
    state = VoiceState.ready;
    layout = null;
    focusId = null;
    speaking.clear();
    _screenShareTracks.clear();
    _listener?.dispose();
    _listener = null;
    r?.removeListener(_onRoomChanged);
    try {
      await r?.disconnect();
      await r?.dispose();
    } catch (_) {}
    if (was && playSound) sounds.play('userLeaveVoice');
    notifyListeners();
  }

  void _onRoomChanged() {
    // A focused tile that no longer exists is cleared, as on web.
    if (focusId != null && focusTile == null) focusId = null;
    _applyVolumes();
    notifyListeners();
  }

  void _applySettings() => _applyVolumes();

  void _applyVolumes() {
    final r = room;
    if (r == null || kIsWeb) return;
    for (final p in r.remoteParticipants.values) {
      for (final pub in p.audioTrackPublications) {
        final track = pub.track;
        if (track is! RemoteAudioTrack) continue;
        final screen = pub.source == TrackSource.screenShareAudio;
        final muted = screen
            ? settings.screenShareMuted(p.identity)
            : settings.userMuted(p.identity);
        final vol = screen
            ? settings.screenShareVolume(p.identity)
            : settings.userVolume(p.identity);
        try {
          rtc.Helper.setVolume(
            muted ? 0 : (vol * settings.outputVolume).clamp(0, 10).toDouble(),
            track.mediaStreamTrack,
          );
        } catch (_) {}
      }
    }
  }

  void _report(Object e) {
    final s = e.toString();
    if (s.contains('NotAllowed')) return;
    lastError.value = s;
  }

  // ---- controls ----

  Future<void> toggleDeafen({bool fromMute = false}) async {
    final r = room;
    if (r == null) return;
    try {
      final next = !settings.deafen;
      settings.deafen = next;
      for (final p in r.remoteParticipants.values) {
        for (final pub in p.audioTrackPublications) {
          if (next) {
            await pub.unsubscribe();
          } else {
            await pub.subscribe();
          }
        }
      }
      if (next) {
        await r.localParticipant?.setMicrophoneEnabled(false);
      } else if (settings.micOn || fromMute) {
        await r.localParticipant?.setMicrophoneEnabled(true);
        if (fromMute) settings.micOn = true;
      }
      sounds.play(next ? 'deafen' : 'undeafen');
    } catch (e) {
      _report(e);
    }
    notifyListeners();
  }

  Future<void> toggleMute() async {
    if (settings.deafen) return toggleDeafen(fromMute: true);
    final r = room;
    if (r == null) return;
    try {
      final enable = !(r.localParticipant?.isMicrophoneEnabled() ?? false);
      await r.localParticipant?.setMicrophoneEnabled(enable);
      settings.micOn = r.localParticipant?.isMicrophoneEnabled() ?? false;
      sounds.play(settings.micOn ? 'unmute' : 'mute');
    } catch (e) {
      _report(e);
    }
    notifyListeners();
  }

  Future<void> toggleCamera() async {
    final r = room;
    if (r == null) return;
    try {
      await r.localParticipant?.setCameraEnabled(!video);
    } catch (e) {
      _report(e);
    }
    notifyListeners();
  }

  Future<void> switchCamera() async {
    final devices = (await Hardware.instance.videoInputs())
        .where((d) => d.deviceId != 'default')
        .toList();
    if (devices.length < 2) return;
    final cam = room?.localParticipant?.videoTrackPublications
        .where((p) => p.source == TrackSource.camera)
        .map((p) => p.track)
        .whereType<LocalVideoTrack>()
        .firstOrNull;
    final current = cam?.currentOptions.deviceId;
    final idx = devices.indexWhere((d) => d.deviceId == current);
    final next = devices[(idx + 1) % devices.length];
    await cam?.restartTrack(
      CameraCaptureOptions(
        deviceId: next.deviceId,
        params: VideoParametersPresets.h720_169,
      ),
    );
    notifyListeners();
  }

  Future<void> stopScreenshare() async {
    try {
      await room?.localParticipant?.setScreenShareEnabled(false);
      sounds.play('streamEnd');
    } catch (e) {
      _report(e);
    }
    notifyListeners();
  }

  Future<void> startScreenshare({
    String? sourceId,
    required String quality,
    required bool audio,
  }) async {
    final r = room;
    if (r == null) return;
    final params = switch (quality) {
      'high' => VideoParametersPresets.h1080_169,
      'text' => VideoParametersPresets.screenShareH1080FPS15,
      _ => VideoParametersPresets.h720_169,
    };
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        // Android screen capture needs the MediaProjection consent prompt plus a
        // foreground service so capture survives while the app is backgrounded.
        if (!await rtc.Helper.requestCapturePermission()) return;
        const androidConfig = FlutterBackgroundAndroidConfig(
          notificationTitle: 'DawnChat',
          notificationText: 'DawnChat is sharing your screen.',
          notificationImportance: AndroidNotificationImportance.normal,
        );
        await FlutterBackground.initialize(androidConfig: androidConfig);
        if (!FlutterBackground.isBackgroundExecutionEnabled) {
          await FlutterBackground.enableBackgroundExecution();
        }
      }
      await r.localParticipant?.setScreenShareEnabled(
        true,
        captureScreenAudio: audio,
        screenShareCaptureOptions: ScreenShareCaptureOptions(
          sourceId: sourceId,
          captureScreenAudio: audio,
          params: params,
          maxFrameRate: quality == 'text' ? 5 : 30,
        ),
      );
      sounds.play('streamStart');
    } catch (e) {
      _report(e);
    }
    notifyListeners();
  }

  void toggleLayout(VoiceLayout l) {
    layout = layout == l ? null : l;
    notifyListeners();
  }

  void resetLayout() {
    layout = null;
    notifyListeners();
  }

  void toggleFocus([VoiceTile? t]) {
    final id = t?.id;
    focusId = (focusId == id || tiles.length < 2) ? null : id;
    notifyListeners();
  }

  void toggleShowBar() {
    showBar = !showBar;
    notifyListeners();
  }

  bool isFocus(VoiceTile t) => t.id == focusId;

  @override
  void dispose() {
    settings.removeListener(_applySettings);
    disconnect(playSound: false);
    super.dispose();
  }
}
