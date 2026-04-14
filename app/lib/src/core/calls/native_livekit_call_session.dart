import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
/// `requestAudioFocus`). On iOS, configuring the session **before** WebRTC initializes can
/// prevent correct remote playout / mic routing with a custom PCM capture path. WebRTC starts
/// first; [CallAudioRoute.applyForCall] still runs after local capture is up (see `_connect`)
/// and for ringback / speaker toggles.
bool get _deferCallAudioUntilAfterLiveKitConnect =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

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
  static const int _audioSamplesPerPush = 480;
  static const int _maxAudioQueueSamples = _audioSamplesPerPush * 25;

  final String _historyId = '${DateTime.now().microsecondsSinceEpoch}';

  /// Dedupes the desktop ongoing-call popout (room + this session instance).
  ///
  /// The OS [WindowController.windowId] is still a UUID; this key is carried in
  /// [DesktopWindowArgs] so only one auxiliary window is tied to this call.
  String get desktopOngoingCallInstanceKey =>
      '${args.matrixRoomId}\x1f$_historyId';

  final List<int> _pcmQueue = [];

  /// PCM chunks must reach Rust in order; overlapping FRB futures can acquire the session
  /// mutex out of order and scramble samples.
  Future<void> _pcmPushChain = Future<void>.value();
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

  /// [Record] may hand off a [Uint8List] slice with an odd [Uint8List.offsetInBytes];
  /// [Int16List.view] requires a 2-byte-aligned offset.
  void _handlePcm16Chunk(Uint8List chunk) {
    if (chunk.length < 2) return;
    final evenByteLen = chunk.length & ~1;
    if (evenByteLen < 2) return;
    final off = chunk.offsetInBytes;
    final Int16List samples;
    if (off.isEven) {
      samples = Int16List.view(chunk.buffer, off, evenByteLen ~/ 2);
    } else {
      final tmp = Uint8List(evenByteLen);
      tmp.setRange(0, evenByteLen, chunk);
      samples = Int16List.view(tmp.buffer, 0, evenByteLen ~/ 2);
    }
    _enqueuePcmFrame(samples);
  }

  void _enqueuePcmFrame(Int16List view) {
    if (_tornDown || _micMuted) return;
    for (var i = 0; i < view.length; i++) {
      _pcmQueue.add(view[i]);
    }
    if (_pcmQueue.length > _maxAudioQueueSamples) {
      final drop = _pcmQueue.length - _maxAudioQueueSamples;
      _pcmQueue.removeRange(0, drop);
    }
    while (_pcmQueue.length >= _audioSamplesPerPush) {
      final chunk = _pcmQueue.sublist(0, _audioSamplesPerPush);
      _pcmQueue.removeRange(0, _audioSamplesPerPush);
      final pcm = List<int>.from(chunk);
      _pcmPushChain = _pcmPushChain.then((_) async {
        if (_tornDown) return;
        try {
          await _lk.pushAudioPcm16(
            pcm: pcm,
            sampleRate: _audioSampleRate,
            numChannels: _audioChannels,
          );
        } catch (e, st) {
          debugPrint('NativeLiveKitCallSession: push audio failed: $e\n$st');
        }
      });
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
    _pcmSub = pcmStream.listen((chunk) {
      _handlePcm16Chunk(chunk);
    }, onError: (_) {});
  }

  Future<void> _pauseMicStream() async {
    _pcmQueue.clear();
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
      _connectionState = s;
      _remoteParticipantCount = n;
      notifyListeners();

      if (args.shouldPlayRingbackAndAloneTimeout &&
          n > 0 &&
          _phase == NativeLiveKitCallPhase.connected) {
        await _stopRingback();
        _aloneTimer?.cancel();
        _aloneTimer = null;
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
    _pcmQueue.clear();
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
