import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:matrix/src/core/navigation/app_navigation.dart';
import 'package:matrix/src/core/permissions/app_runtime_permissions.dart';
import 'package:matrix/src/core/calls/call_audio_route.dart';
import 'package:matrix/src/core/calls/call_history_store.dart';
import 'package:matrix/src/core/calls/android_call_launch.dart';
import 'package:matrix/src/core/calls/livekit_camera_i420.dart';
import 'package:matrix/src/core/calls/livekit_native_bridge.dart';
import 'package:matrix/src/core/calls/native_livekit_call_local_audio.dart';
import 'package:matrix/src/core/calls/native_livekit_call_host.dart';
import 'package:matrix/src/core/calls/ringback_wav.dart';
import 'package:matrix_sdk/matrix_sdk.dart';

enum NativeLiveKitCallPhase { idle, connecting, connected, ended }

/// On Android, configuring [AudioSession] before Rust LiveKit/libwebrtc connects has been
/// observed to crash the process (SIGSEGV on a `tokio-rt-worker` right after
/// `requestAudioFocus`). On iOS and macOS, configuring the session **before** WebRTC initializes
/// can prevent correct remote playout / mic routing with a custom PCM capture path. WebRTC starts
/// first; [CallAudioRoute.applyForCall] still runs after local capture is up (see `_connect`)
/// and for ringback / speaker toggles.
bool get _deferCallAudioUntilAfterLiveKitConnect =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);

@immutable
class NativeLiveKitCallArgs {
  const NativeLiveKitCallArgs({
    required this.matrixClient,
    required this.livekitUrl,
    required this.accessToken,
    required this.title,
    required this.matrixRoomId,
    this.voiceOnly = false,

    /// Full-screen layout with camera controls (can be true while [voiceOnly] is true if the user
    /// chose a video-style call but no camera token/track is available).
    this.preferVideoCallUi = false,
    this.localDisplayName,
    this.localAvatarMxc,
    this.isDirectRoom = false,
    this.joinedExisting = false,
    this.historyDirection = CallHistoryDirection.outgoing,
    this.rtcNotificationEventId,
    this.liveKitBridge,
    this.debugSkipPlatformAudioDevices = false,
    this.debugSkipCallHistoryForTest = false,
    this.localAudioForTest,
  });

  final MatrixClient matrixClient;

  /// When null, [DefaultLiveKitNativeBridge] is used (production FRB).
  final LiveKitNativeBridge? liveKitBridge;
  final String livekitUrl;
  final String accessToken;
  final String title;
  final String matrixRoomId;

  /// LiveKit session: no published camera track when true.
  final bool voiceOnly;

  /// Whether to show the video call shell (self preview / avatar, camera toggle).
  final bool preferVideoCallUi;

  /// Logged-in user label when local video is unavailable (camera off / no hardware).
  final String? localDisplayName;

  /// Profile avatar MXC URI for the local placeholder, if known.
  final String? localAvatarMxc;
  final bool isDirectRoom;
  final bool joinedExisting;
  final CallHistoryDirection historyDirection;

  /// Set when [MatrixClient.sendRtcRingNotification] succeeded (outgoing ring).
  final String? rtcNotificationEventId;

  /// Skips real `record` / `just_audio` (no platform plugins). Use with [liveKitBridge] fakes in tests.
  @visibleForTesting
  final bool debugSkipPlatformAudioDevices;

  /// Skips [CallHistoryStore] start/end so tests do not hit [MatrixService] persistence.
  @visibleForTesting
  final bool debugSkipCallHistoryForTest;

  /// When non-null, used instead of [createNativeLiveKitCallLocalAudio] (tests only).
  @visibleForTesting
  final NativeLiveKitCallLocalAudio? localAudioForTest;

  /// Ringback + 30s alone hangup only for outgoing “new” calls — not incoming CallKit.
  bool get shouldPlayRingbackAndAloneTimeout =>
      historyDirection == CallHistoryDirection.outgoing && !joinedExisting;
}

/// Owns LiveKit connection, local capture, ringback, and in-call toggles. Survives popping the UI route.
class NativeLiveKitCallSession extends ChangeNotifier {
  NativeLiveKitCallSession(this.args)
    : _speakerOn =
          args.historyDirection == CallHistoryDirection.incoming ||
          !args.voiceOnly ||
          args.preferVideoCallUi,
      _lk = args.liveKitBridge ?? DefaultLiveKitNativeBridge.instance,
      _localAudio = args.localAudioForTest ??
          createNativeLiveKitCallLocalAudio(
            noop: args.debugSkipPlatformAudioDevices,
          );

  final NativeLiveKitCallArgs args;
  final LiveKitNativeBridge _lk;
  final NativeLiveKitCallLocalAudio _localAudio;

  static const int _audioSampleRate = 48000;
  static const int _audioChannels = 1;

  final String _historyId = '${DateTime.now().microsecondsSinceEpoch}';

  /// Dedupes the desktop ongoing-call popout (room + this session instance).
  ///
  /// The OS [WindowController.windowId] is still a UUID; this key is carried in
  /// [DesktopWindowArgs] so only one auxiliary window is tied to this call.
  String get desktopOngoingCallInstanceKey =>
      '${args.matrixRoomId}\x1f$_historyId';

  /// Bytes from the mic plugin (`record`) per [Uint8List] event (diagnostics only).
  int _diagMicPcmEvents = 0;

  /// Completed [LiveKitNativeBridge.pushAudioPcm16] calls (one per `record` chunk after alignment).
  int _diagAudioPushSuccess = 0;

  /// Failed pushes or FRB errors when sending PCM.
  int _diagAudioPushFailures = 0;

  Timer? _audioUplinkDiagTimer;

  /// PCM chunks must reach Rust in order; overlapping FRB futures can acquire the session
  /// mutex out of order and scramble samples.
  Future<void> _pcmPushChain = Future<void>.value();

  /// Remote PCM pulls must not overlap [feedUint8FromStream] calls on the downlink player.
  Future<void> _remoteDownlinkChain = Future<void>.value();
  Timer? _remoteAudioPullTimer;
  FlutterSoundPlayer? _remoteDownlinkPlayer;
  StreamSubscription<Uint8List>? _pcmSub;
  CameraController? _camera;
  bool _cameraStreamRunning = false;
  bool _videoPushBusy = false;
  DateTime _lastVideoPush = DateTime.fromMillisecondsSinceEpoch(0);
  int _videoRotation = 0;

  bool _historyStarted = false;
  bool _tornDown = false;
  bool _connectStarted = false;
  Object? _error;
  NativeLiveKitCallPhase _phase = NativeLiveKitCallPhase.idle;
  String _connectionState = 'idle';
  int _remoteParticipantCount = 0;
  Timer? _statePoll;
  Timer? _aloneTimer;
  Timer? _callDurationTicker;
  Timer? _micLevelDecayTimer;

  /// LiveKit published a local camera track (at connect or after [livekitSessionPublishLocalCameraTrack]).
  bool _videoTrackReadyInRust = false;
  bool _hadRemoteParticipant = false;

  /// Confirms [livekitSessionRemoteParticipantCount] stayed at 0 across polls (avoids one-off glitches).
  int _consecutiveRemoteZeroPolls = 0;
  DateTime? _callDurationEpoch;

  bool _hangUpInFlight = false;

  /// Actual LiveKit mode used after connect (may differ from [args.voiceOnly] if the camera failed).
  bool _connectedAsVoiceOnly = false;

  bool _micMuted = false;
  bool _cameraMuted = false;

  /// Local hold: mic + camera publishing paused (Matrix/LiveKit “hold” UX).
  bool _callHeld = false;

  /// Earpiece when `false` (voice default); loudspeaker when `true` (video default).
  bool _speakerOn;
  StreamSubscription<String>? _declineSub;
  String? _userVisibleOutcome;

  NativeLiveKitCallPhase get phase => _phase;
  Object? get error => _error;
  String get connectionState => _connectionState;
  int get remoteParticipantCount => _remoteParticipantCount;
  bool get micMuted => _micMuted;
  bool get cameraMuted => _cameraMuted;
  bool get callHeld => _callHeld;
  bool get speakerOn => _speakerOn;
  bool get voiceOnly => args.voiceOnly;
  bool get preferVideoCallUi => args.preferVideoCallUi;
  String get title => args.title;

  /// True when the local camera preview is actively streaming to LiveKit.
  bool get hasLocalVideoPreview =>
      !args.voiceOnly &&
      _camera != null &&
      _camera!.value.isInitialized &&
      !_cameraMuted &&
      _cameraStreamRunning;
  CameraController? get cameraController => _camera;
  int get videoRotation => _videoRotation;
  String? get userVisibleOutcome => _userVisibleOutcome;

  /// PiP / preview while minimized: local camera preview is active.
  bool get showMinimizedVideoPip => hasLocalVideoPreview;

  bool get callDurationEpochStarted => _callDurationEpoch != null;

  Duration get connectedCallDuration {
    final start = _callDurationEpoch;
    if (start == null) return Duration.zero;
    return DateTime.now().difference(start);
  }

  /// Debug: mic PCM events from `record` since connect (not samples).
  int get debugUplinkMicPcmEvents => _diagMicPcmEvents;

  /// Debug: successful FRB [pushAudioPcm16] invocations (each ≈10 ms @ 48 kHz mono).
  int get debugUplinkAudioPushSuccess => _diagAudioPushSuccess;

  /// Debug: failed [pushAudioPcm16] calls.
  int get debugUplinkAudioPushFailures => _diagAudioPushFailures;

  /// Smoothed mic input \[0,1\] from captured PCM (UI waveform).
  double get micCaptureLevel => _micCaptureLevel;

  double _micCaptureLevel = 0;
  DateTime? _lastPcmChunkAt;
  DateTime? _lastMicLevelNotify;

  String get connectedCallDurationLabel {
    if (_callDurationEpoch == null) return '';
    final d = connectedCallDuration;
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  bool get isFullyConnected =>
      _phase == NativeLiveKitCallPhase.connected && _error == null;

  /// Whether popping the route should tear down an in-progress or failed connect (not minimize).
  bool get shouldAbortOnRoutePop =>
      !_tornDown &&
      _connectStarted &&
      _phase != NativeLiveKitCallPhase.connected &&
      _phase != NativeLiveKitCallPhase.ended;

  /// Start connect + media once (idempotent).
  Future<void> ensureStarted() async {
    if (_connectStarted || _tornDown) return;
    _connectStarted = true;
    await _connect();
  }

  Future<void> abortBecausePoppedDuringConnect() async {
    if (!shouldAbortOnRoutePop) return;
    await hangUp();
  }

  Future<void> hangUp({String? historyEndReason}) async {
    if (_hangUpInFlight) return;
    if (_tornDown) {
      _popRootCallRouteIfPossible();
      NativeLiveKitCallHost.instance.detachSession(this);
      if (AndroidCallOnlyMode.isActive) {
        AndroidCallOnlyMode.markInactive();
        unawaited(AndroidCallLaunch.finishCallOnlyTask());
      }
      return;
    }
    _hangUpInFlight = true;
    final host = NativeLiveKitCallHost.instance;
    // Snapshot before async work: host flags match whether the full-screen call route may be open.
    final shouldPopRoute = host.routeVisible || host.callScreenRouteOnStack;
    host.setSuppressMinimizedBannerDuringHangUp(true);
    try {
      await _silenceRingbackImmediately();
      if (!_tornDown) {
        // Pop the call route first so the UI closes immediately; teardown can take hundreds of ms.
        if (shouldPopRoute) {
          _popRootCallRouteIfPossible();
        }
        try {
          await _tearDown(historyEndReason: historyEndReason);
        } catch (e, st) {
          debugPrint('NativeLiveKitCallSession: _tearDown failed: $e\n$st');
          await _emergencyRustClose();
        }
      }
    } finally {
      NativeLiveKitCallHost.instance.detachSession(this);
      host.setSuppressMinimizedBannerDuringHangUp(false);
      _hangUpInFlight = false;
    }
    _maybeShowOutcomeSnackBar();
    if (AndroidCallOnlyMode.isActive) {
      AndroidCallOnlyMode.markInactive();
      unawaited(AndroidCallLaunch.finishCallOnlyTask());
    }
  }

  Future<void> _emergencyRustClose() async {
    try {
      await _lk.close();
    } catch (e, st) {
      debugPrint('NativeLiveKitCallSession: emergency close: $e\n$st');
    }
  }

  void _popRootCallRouteIfPossible() {
    final nav = AppNavigation.rootNavigatorKey.currentState;
    if (nav != null && nav.mounted && nav.canPop()) {
      nav.pop();
    }
  }

  void _maybeShowOutcomeSnackBar() {
    final msg = _userVisibleOutcome;
    if (msg == null || msg.isEmpty) return;
    final ctx = AppNavigation.rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showTransientSnack(String message) {
    final ctx = AppNavigation.rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    ScaffoldMessenger.maybeOf(
      ctx,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> setMicrophoneMuted(bool muted) async {
    if (_callHeld && !muted) return;
    if (_micMuted == muted) return;
    _micMuted = muted;
    if (muted) {
      _micCaptureLevel = 0;
      _lastPcmChunkAt = null;
    }
    notifyListeners();
    try {
      await _lk.setMicrophoneMuted(muted: muted);
    } catch (_) {}
    if (muted) {
      await _pauseMicStream();
    } else if (_phase == NativeLiveKitCallPhase.connected) {
      await _resumeMicStream();
    }
  }

  Future<void> setSpeakerOn(bool on) async {
    if (_speakerOn == on) return;
    _speakerOn = on;
    notifyListeners();
    await _applyCallAudioRoute();
  }

  /// Local hold: mute mic and stop camera publish/stream until resumed.
  Future<void> setCallHeld(bool held) async {
    if (_callHeld == held || _tornDown) return;
    _callHeld = held;
    notifyListeners();
    if (held) {
      await setMicrophoneMuted(true);
      if (!args.voiceOnly || _videoTrackReadyInRust || _camera != null) {
        await setCameraMuted(true);
      }
    } else {
      await setMicrophoneMuted(false);
    }
  }

  Future<void> setCameraMuted(bool muted) async {
    if (_callHeld && !muted) return;
    if (_cameraMuted == muted) return;

    if (muted) {
      _cameraMuted = true;
      notifyListeners();
      try {
        await _lk.setCameraMuted(muted: true);
      } catch (_) {}
      await _stopCameraStream();
      return;
    }

    final ctx = AppNavigation.rootNavigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      final camOk = await AppRuntimePermissions.ensureCamera(
        ctx,
        title: 'Camera',
        rationale:
            'Turning on video shares your camera with people in this call. '
            'You can enable access in Settings if you previously declined.',
      );
      if (!camOk) return;
    }

    if (!_videoTrackReadyInRust) {
      try {
        await _lk.publishLocalCameraTrack();
        _videoTrackReadyInRust = true;
      } catch (e) {
        debugPrint('publishLocalCameraTrack: $e');
        _showTransientSnack('Could not start video');
        return;
      }
    }

    if (_camera == null) {
      try {
        _camera = await _prepareCameraController();
        notifyListeners();
      } catch (e) {
        debugPrint('_prepareCameraController: $e');
        _showTransientSnack('No camera available');
        return;
      }
    }

    _cameraMuted = false;
    notifyListeners();
    try {
      await _lk.setCameraMuted(muted: false);
    } catch (_) {}
    if (_phase == NativeLiveKitCallPhase.connected) {
      await _startCameraStreamIfNeeded();
    }
  }

  Future<void> _applyCallAudioRoute() async {
    try {
      await CallAudioRoute.applyForCall(speakerOn: _speakerOn);
    } catch (e) {
      debugPrint('CallAudioRoute.applyForCall: $e');
    }
  }

  /// Stop ringback as fast as possible (volume + stop) so end-call feels instant.
  Future<void> _silenceRingbackImmediately() async {
    try {
      await _localAudio.setRingVolume(0);
    } catch (_) {}
    await _stopRingback();
  }

  /// Plays the first remote mic via Rust [NativeAudioStream] → ring buffer → FRB pull → PCM stream.
  Future<void> _startRemoteDownlinkPlayback() async {
    if (kIsWeb || args.debugSkipPlatformAudioDevices || _remoteDownlinkPlayer != null) {
      return;
    }
    FlutterSoundPlayer? p;
    try {
      p = FlutterSoundPlayer();
      await p.openPlayer();
      await p.startPlayerFromStream(
        codec: Codec.pcm16,
        interleaved: true,
        numChannels: _audioChannels,
        sampleRate: _audioSampleRate,
        bufferSize: 8192,
      );
      if (_tornDown || _phase != NativeLiveKitCallPhase.connected) {
        await p.closePlayer();
        return;
      }
      _remoteDownlinkPlayer = p;
      p = null;
      _remoteAudioPullTimer?.cancel();
      _remoteAudioPullTimer = Timer.periodic(const Duration(milliseconds: 10), (_) {
        _enqueueRemoteDownlinkPull();
      });
    } catch (e, st) {
      debugPrint('NativeLiveKitCallSession: remote downlink start failed: $e\n$st');
    } finally {
      if (p != null) {
        try {
          await p.closePlayer();
        } catch (_) {}
      }
    }
  }

  void _enqueueRemoteDownlinkPull() {
    if (_tornDown || _phase != NativeLiveKitCallPhase.connected) return;
    _remoteDownlinkChain = _remoteDownlinkChain.then((_) => _pullRemoteDownlinkOnce());
  }

  Future<void> _pullRemoteDownlinkOnce() async {
    final player = _remoteDownlinkPlayer;
    if (player == null || _tornDown || _phase != NativeLiveKitCallPhase.connected) {
      return;
    }
    try {
      final chunk = await _lk.pullRemoteAudioPcm16(maxSamples: 960);
      if (chunk.isEmpty) return;
      final bytes = Uint8List(chunk.length * 2);
      Int16List.sublistView(bytes).setRange(0, chunk.length, chunk);
      await player.feedUint8FromStream(bytes);
    } catch (e, st) {
      if (!_tornDown) {
        debugPrint('NativeLiveKitCallSession: remote downlink pull: $e\n$st');
      }
    }
  }

  Future<void> _stopRemoteDownlinkPlayback() async {
    _remoteAudioPullTimer?.cancel();
    _remoteAudioPullTimer = null;
    _remoteDownlinkChain = Future<void>.value();
    final p = _remoteDownlinkPlayer;
    _remoteDownlinkPlayer = null;
    if (p != null) {
      try {
        await p.stopPlayer();
      } catch (_) {}
      try {
        await p.closePlayer();
      } catch (_) {}
    }
  }

  /// `record` often delivers a [Uint8List] view into a larger buffer with an odd
  /// [offsetInBytes]; [Int16List.sublistView] requires 2-byte alignment. Always copy into a
  /// fresh [Uint8List] before decoding (same approach as `flutter_livekit_demo`).
  ///
  /// Uplink path: PCM16 → [LiveKitNativeBridge.pushAudioPcm16] → Rust
  /// [livekit_session_push_audio_pcm16] (buffers to 10 ms there) → [NativeAudioSource::capture_frame].
  ///
  /// Matches `flutter_livekit_demo`: one push per `record` chunk (aligned copy), serialized by
  /// [_pcmPushChain] so FRB does not reorder mutex acquisition.
  void _handlePcm16Chunk(Uint8List chunk) {
    if (chunk.length < 2 || _tornDown || _micMuted) return;
    _diagMicPcmEvents++;
    final n = chunk.length - (chunk.length % 2);
    if (n < 2) return;
    final aligned = Uint8List(n);
    aligned.setRange(0, n, chunk);
    final samples = Int16List.sublistView(aligned);
    _lastPcmChunkAt = DateTime.now();
    _updateMicLevelFromInt16(samples);
    final pcm = List<int>.from(samples);
    _pcmPushChain = _pcmPushChain.then((_) async {
      if (_tornDown || _micMuted) return;
      try {
        await _lk.pushAudioPcm16(
          pcm: pcm,
          sampleRate: _audioSampleRate,
          numChannels: _audioChannels,
        );
        _diagAudioPushSuccess++;
      } catch (e, st) {
        _diagAudioPushFailures++;
        debugPrint('NativeLiveKitCallSession: push audio failed: $e\n$st');
      }
    });
  }

  void _updateMicLevelFromInt16(Int16List samples) {
    if (_tornDown || _micMuted || samples.isEmpty) return;
    var peak = 0;
    for (var i = 0; i < samples.length; i++) {
      final a = samples[i].abs();
      if (a > peak) peak = a;
    }
    final instant = (peak / 32768.0).clamp(0.0, 1.0);
    _micCaptureLevel = (_micCaptureLevel * 0.8 + instant * 0.2).clamp(0.0, 1.0);
    _maybeNotifyMicLevel();
  }

  void _maybeNotifyMicLevel() {
    final now = DateTime.now();
    final last = _lastMicLevelNotify;
    if (last == null || now.difference(last) >= const Duration(milliseconds: 33)) {
      _lastMicLevelNotify = now;
      notifyListeners();
    }
  }

  Future<void> _prepareMicPrerequisites() async {
    await _localAudio.prepareMicPrerequisites();
  }

  Future<CameraController?> _prepareCameraController() async {
    final cams = await availableCameras();
    if (cams.isEmpty) {
      throw Exception('No camera available.');
    }
    final desc = cams.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cams.first,
    );
    _videoRotation = desc.sensorOrientation;
    notifyListeners();
    final controller = CameraController(
      desc,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await controller.initialize();
    if (!controller.value.isInitialized) {
      await controller.dispose();
      throw Exception('Camera failed to initialize.');
    }
    return controller;
  }

  void _maybeStartCallDurationTicker() {
    if (_tornDown || _phase != NativeLiveKitCallPhase.connected) return;
    if (_callDurationEpoch != null) return;
    _callDurationEpoch = DateTime.now();
    _callDurationTicker?.cancel();
    _callDurationTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_tornDown) notifyListeners();
    });
  }

  Future<void> _startMicStream() async {
    final pcmStream = await _localAudio.openMicPcmStream(
      sampleRate: _audioSampleRate,
      numChannels: _audioChannels,
    );
    _pcmSub = pcmStream.listen(
      _handlePcm16Chunk,
      onError: (Object e, StackTrace st) {
        debugPrint('NativeLiveKitCallSession: mic PCM stream error: $e\n$st');
      },
    );
  }

  Future<void> _pauseMicStream() async {
    await _pcmSub?.cancel();
    _pcmSub = null;
    try {
      await _localAudio.stopMicCapture();
    } catch (_) {}
  }

  Future<void> _resumeMicStream() async {
    if (_tornDown || _micMuted) return;
    try {
      await _startMicStream();
    } catch (_) {}
  }

  Future<void> _startCameraStreamIfNeeded() async {
    if (_camera == null || _cameraMuted || _cameraStreamRunning || _tornDown) {
      return;
    }
    await _camera!.startImageStream(_onCameraImage);
    _cameraStreamRunning = true;
  }

  Future<void> _stopCameraStream() async {
    try {
      if (_cameraStreamRunning && _camera != null) {
        await _camera!.stopImageStream();
      }
    } catch (_) {}
    _cameraStreamRunning = false;
  }

  /// Matrix `m.rtc.decline` for outgoing rings: subscribed after [livekitSessionConnect]
  /// succeeds so Tokio work does not overlap WebRTC setup on Android (stability). A decline in
  /// the first ~hundred ms after connect is unlikely; if that matters, tighten server/client UX.
  void _attachDeclineWatcherIfNeeded() {
    if (_declineSub != null || _tornDown) return;
    final rtcNid = args.rtcNotificationEventId;
    if (rtcNid == null ||
        rtcNid.isEmpty ||
        !args.shouldPlayRingbackAndAloneTimeout) {
      return;
    }
    _declineSub = args.matrixClient
        .startCallDeclineWatcher(
          roomId: args.matrixRoomId,
          rtcNotificationEventId: rtcNid,
        )
        .listen((_) {
          unawaited(_onCalleeDeclinedMatrix());
        }, onError: (_) {});
  }

  Future<void> _connect() async {
    _diagMicPcmEvents = 0;
    _diagAudioPushSuccess = 0;
    _diagAudioPushFailures = 0;
    _audioUplinkDiagTimer?.cancel();
    _audioUplinkDiagTimer = null;
    _micLevelDecayTimer?.cancel();
    _micLevelDecayTimer = null;
    _micCaptureLevel = 0;
    _lastPcmChunkAt = null;
    _lastMicLevelNotify = null;

    _phase = NativeLiveKitCallPhase.connecting;
    _error = null;
    notifyListeners();
    if (!_deferCallAudioUntilAfterLiveKitConnect) {
      await _applyCallAudioRoute();
    }

    CameraController? preparedCam;
    try {
      await _prepareMicPrerequisites();

      var effectiveVoiceOnly = args.voiceOnly;
      if (!effectiveVoiceOnly) {
        try {
          preparedCam = await _prepareCameraController();
        } catch (e) {
          debugPrint(
            'NativeLiveKitCallSession: no camera at connect, using voice-only: $e',
          );
          effectiveVoiceOnly = true;
        }
      }

      await _lk.connect(
        url: args.livekitUrl,
        token: args.accessToken,
        voiceOnly: effectiveVoiceOnly,
      );

      if (_tornDown) {
        await preparedCam?.dispose();
        try {
          await _lk.close();
        } catch (_) {}
        return;
      }

      // Establish voice-communication audio focus *before* opening the `record` stream on
      // Android/iOS. Starting capture first leaves AudioRecord in the wrong mode; uplink can stay
      // silent until teardown. A second [CallAudioRoute.applyForCall] after capture still runs
      // below so routing survives any `record` session reconfiguration.
      if (_deferCallAudioUntilAfterLiveKitConnect) {
        await _applyCallAudioRoute();
      }

      // After LiveKit/WebRTC is up: register Matrix decline watcher. Doing this earlier
      // overlapped heavy Tokio work (event handlers + FRB stream) with `Room::connect`
      // and contributed to Android SIGSEGV. Fast declines during connect are unlikely.
      _attachDeclineWatcherIfNeeded();

      _videoTrackReadyInRust = !effectiveVoiceOnly;
      _camera = preparedCam;
      preparedCam = null;
      _cameraMuted = !(_videoTrackReadyInRust && _camera != null);
      _connectedAsVoiceOnly = effectiveVoiceOnly;

      try {
        if (!_micMuted) {
          await _startMicStream();
        }
      } catch (e) {
        await _camera?.dispose();
        _camera = null;
        try {
          await _lk.close();
        } catch (_) {}
        _connectStarted = false;
        rethrow;
      }

      try {
        await _startCameraStreamIfNeeded();
      } catch (e, st) {
        debugPrint(
          'NativeLiveKitCallSession: camera preview stream failed: $e\n$st',
        );
        await _stopCameraStream();
        await _camera?.dispose();
        _camera = null;
        _cameraStreamRunning = false;
        if (_videoTrackReadyInRust) {
          try {
            await _lk.setCameraMuted(muted: true);
          } catch (_) {}
        }
        _cameraMuted = true;
        notifyListeners();
      }

      // `record` can reconfigure the platform audio session; re-apply call routing
      // so WebRTC remote playout + voiceCommunication mode stay consistent.
      await _applyCallAudioRoute();

      if (_tornDown) {
        await _stopLocalMedia();
        try {
          await _lk.close();
        } catch (_) {}
        return;
      }

      _phase = NativeLiveKitCallPhase.connected;
      _error = null;
      notifyListeners();

      unawaited(_startRemoteDownlinkPlayback());

      if (kDebugMode) {
        _audioUplinkDiagTimer?.cancel();
        _audioUplinkDiagTimer = Timer.periodic(const Duration(seconds: 2), (_) {
          if (_tornDown || _phase != NativeLiveKitCallPhase.connected) return;
          developer.log(
            'uplink micPcmEvents=$_diagMicPcmEvents pushOk=$_diagAudioPushSuccess '
            'pushFail=$_diagAudioPushFailures micMuted=$_micMuted',
            name: 'matrix_native_livekit',
          );
        });
      }

      _micLevelDecayTimer?.cancel();
      _micLevelDecayTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
        if (_tornDown || _phase != NativeLiveKitCallPhase.connected || _micMuted) {
          return;
        }
        final last = _lastPcmChunkAt;
        final now = DateTime.now();
        if (last != null && now.difference(last) < const Duration(milliseconds: 320)) {
          return;
        }
        if (_micCaptureLevel > 0.02) {
          _micCaptureLevel = (_micCaptureLevel * 0.88).clamp(0.0, 1.0);
          _maybeNotifyMicLevel();
        } else if (_micCaptureLevel > 0) {
          _micCaptureLevel = 0;
          _maybeNotifyMicLevel();
        }
      });

      try {
        final initialRemote = await _lk.remoteParticipantCount();
        _remoteParticipantCount = initialRemote;
        if (initialRemote > 0) {
          _hadRemoteParticipant = true;
          _maybeStartCallDurationTicker();
        }
        notifyListeners();
      } catch (_) {}

      if (!args.debugSkipCallHistoryForTest) {
        CallHistoryStore.instance.startSession(
          id: _historyId,
          roomId: args.matrixRoomId,
          roomName: args.title,
          isDirectRoom: args.isDirectRoom,
          direction: args.historyDirection,
          voiceOnly: _connectedAsVoiceOnly,
          joinedExisting: args.joinedExisting,
        );
        _historyStarted = true;
      }

      _statePoll?.cancel();
      _statePoll = Timer.periodic(const Duration(milliseconds: 300), (_) {
        unawaited(_pollRoom());
      });
      unawaited(_pollRoom());

      if (args.shouldPlayRingbackAndAloneTimeout) {
        unawaited(_startRingbackIfAlone());
        _scheduleAloneTimeout();
      }
    } catch (e) {
      await preparedCam?.dispose();
      _error = e;
      _phase = NativeLiveKitCallPhase.idle;
      _connectStarted = false;
      notifyListeners();
    }
  }

  Future<void> _pollRoom() async {
    if (_tornDown) {
      return;
    }
    try {
      final s = await _lk.connectionState();
      final n = await _lk.remoteParticipantCount();
      final prevRemote = _remoteParticipantCount;
      _connectionState = s;
      _remoteParticipantCount = n;
      notifyListeners();

      if (args.shouldPlayRingbackAndAloneTimeout &&
          n > 0 &&
          _phase == NativeLiveKitCallPhase.connected) {
        await _stopRingback();
        _aloneTimer?.cancel();
        _aloneTimer = null;
        // Ringback + `just_audio` can leave the platform session in a state where WebRTC never
        // binds remote playout; re-apply the same route used for the call after ringback stops.
        await _applyCallAudioRoute();
      }

      // First remote joins: refresh voice session so recv path (remote audio) is not stuck after
      // mic/`record` started (common on iOS when playout never attached until route is reset).
      if (n > 0 && prevRemote == 0 && _phase == NativeLiveKitCallPhase.connected) {
        await _applyCallAudioRoute();
      }

      if (n > 0) {
        _hadRemoteParticipant = true;
        _consecutiveRemoteZeroPolls = 0;
        _maybeStartCallDurationTicker();
      } else if (_phase == NativeLiveKitCallPhase.connected &&
          _hadRemoteParticipant) {
        _consecutiveRemoteZeroPolls++;
      }

      final sl = s.toLowerCase();
      final roomDisconnected =
          _phase == NativeLiveKitCallPhase.connected &&
          _hadRemoteParticipant &&
          sl.contains('disconnect');

      final remoteLeftConfirmed =
          _phase == NativeLiveKitCallPhase.connected &&
          _hadRemoteParticipant &&
          n == 0 &&
          _consecutiveRemoteZeroPolls >= 2;

      if (remoteLeftConfirmed || roomDisconnected) {
        _userVisibleOutcome = 'Call ended';
        notifyListeners();
        unawaited(hangUp(historyEndReason: 'Remote ended call'));
      }
    } catch (_) {}
  }

  Future<void> _startRingbackIfAlone() async {
    if (_tornDown || !args.shouldPlayRingbackAndAloneTimeout) return;
    if (_remoteParticipantCount > 0) return;
    try {
      await _applyCallAudioRoute();
      final wav = await ensureRingbackWavFile();
      await _localAudio.startRingbackLoopingFile(wav.path);
    } catch (e) {
      debugPrint('Ringback failed: $e');
    }
  }

  Future<void> _stopRingback() async {
    try {
      await _localAudio.stopRingback();
    } catch (_) {}
  }

  void _scheduleAloneTimeout() {
    if (!args.shouldPlayRingbackAndAloneTimeout) return;
    _aloneTimer?.cancel();
    _aloneTimer = Timer(const Duration(seconds: 30), () {
      unawaited(_onAloneTimeout());
    });
  }

  Future<void> _onAloneTimeout() async {
    if (_tornDown || _remoteParticipantCount > 0) return;
    _userVisibleOutcome = 'No answer';
    notifyListeners();
    await _stopRingback();
    await hangUp(historyEndReason: 'No answer');
  }

  Future<void> _onCalleeDeclinedMatrix() async {
    if (_tornDown) return;
    _userVisibleOutcome = 'Call declined';
    notifyListeners();
    await _stopRingback();
    _aloneTimer?.cancel();
    _aloneTimer = null;
    await hangUp(historyEndReason: 'Declined');
  }

  void _onCameraImage(CameraImage image) {
    if (_videoPushBusy || _tornDown || _cameraMuted) return;
    final now = DateTime.now();
    if (now.difference(_lastVideoPush) < const Duration(milliseconds: 66)) {
      return;
    }
    final i420 = tightI420FromCameraImage(image);
    if (i420 == null) return;

    _videoPushBusy = true;
    _lastVideoPush = now;
    final ts = now.microsecondsSinceEpoch;
    unawaited(
      _lk
          .pushVideoI420(
            width: image.width,
            height: image.height,
            data: i420,
            timestampUs: ts,
            rotationDegrees: _videoRotation,
          )
          .whenComplete(() {
            _videoPushBusy = false;
          }),
    );
  }

  Future<void> _stopLocalMedia() async {
    await _stopRingback();
    await _stopRemoteDownlinkPlayback();
    _pcmPushChain = Future<void>.value();
    await _pcmSub?.cancel();
    _pcmSub = null;
    await _stopCameraStream();
    await _camera?.dispose();
    _camera = null;
    try {
      await _localAudio.stopMicCapture();
    } catch (_) {}
  }

  Future<void> _tearDown({String? historyEndReason}) async {
    if (_tornDown) return;
    _tornDown = true;
    _audioUplinkDiagTimer?.cancel();
    _audioUplinkDiagTimer = null;
    _micLevelDecayTimer?.cancel();
    _micLevelDecayTimer = null;
    _callHeld = false;
    _consecutiveRemoteZeroPolls = 0;
    _aloneTimer?.cancel();
    _aloneTimer = null;
    _callDurationTicker?.cancel();
    _callDurationTicker = null;
    _statePoll?.cancel();
    _statePoll = null;
    try {
      await _declineSub?.cancel();
    } catch (e, st) {
      debugPrint('NativeLiveKitCallSession: declineSub cancel: $e\n$st');
    }
    _declineSub = null;

    try {
      final rtcNid = args.rtcNotificationEventId;
      if (rtcNid != null && rtcNid.isNotEmpty) {
        await MatrixClient.endCallDeclineWatcherForRtcNotification(
          roomId: args.matrixRoomId,
          rtcNotificationEventId: rtcNid,
        );
      }
    } catch (e, st) {
      debugPrint('NativeLiveKitCallSession: endCallDeclineWatcher: $e\n$st');
    }

    try {
      await _stopLocalMedia();
    } catch (e, st) {
      debugPrint('NativeLiveKitCallSession: _stopLocalMedia: $e\n$st');
    }

    try {
      await _lk.close();
    } catch (e, st) {
      debugPrint('NativeLiveKitCallSession: livekit close: $e\n$st');
    }

    try {
      await _localAudio.dispose();
    } catch (_) {}

    try {
      if (_historyStarted) {
        await CallHistoryStore.instance.endSession(
          _historyId,
          roomId: args.matrixRoomId,
          endReason: historyEndReason,
        );
      }
    } catch (e, st) {
      debugPrint(
        'NativeLiveKitCallSession: CallHistoryStore.endSession: $e\n$st',
      );
    }

    try {
      await CallAudioRoute.releaseAfterCall();
    } catch (_) {}

    _phase = NativeLiveKitCallPhase.ended;
    notifyListeners();
  }
}
