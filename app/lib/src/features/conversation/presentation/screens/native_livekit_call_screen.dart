import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:matrix/src/core/calls/call_mic_activity_waveform.dart';
import 'package:matrix/src/core/calls/call_proximity_controller.dart';
import 'package:matrix/src/core/calls/native_livekit_call_host.dart';
import 'package:matrix/src/core/calls/native_livekit_call_session.dart';
import 'package:matrix/src/core/matrix_avatar_disk_cache.dart';
import 'package:matrix/src/theme/matrix_theme.dart';
import 'package:matrix_sdk/matrix_sdk.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Full-screen native LiveKit call UI. [NativeLiveKitCallHost] must already reference the session.
class NativeLiveKitCallScreen extends StatefulWidget {
  const NativeLiveKitCallScreen({super.key});

  @override
  State<NativeLiveKitCallScreen> createState() =>
      _NativeLiveKitCallScreenState();
}

class _NativeLiveKitCallScreenState extends State<NativeLiveKitCallScreen> {
  NativeLiveKitCallSession? _session;
  final CallProximityController _proximity = CallProximityController();

  @override
  void initState() {
    super.initState();
    _session = NativeLiveKitCallHost.instance.session;
    _session?.addListener(_onSession);
    if (_session != null) {
      unawaited(
        _session!.ensureStarted().then((_) {
          if (mounted) unawaited(_syncCallHardware());
        }),
      );
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
  }

  void _onSession() {
    unawaited(_syncCallHardware());
    if (mounted) setState(() {});
  }

  Future<void> _syncCallHardware() async {
    final s = _session;
    if (s == null || s.phase != NativeLiveKitCallPhase.connected) {
      await _proximity.dispose();
      if (!kIsWeb) {
        try {
          await WakelockPlus.disable();
        } catch (_) {}
      }
      return;
    }
    if (s.speakerOn) {
      await _proximity.dispose();
      if (!kIsWeb) {
        try {
          await WakelockPlus.enable();
        } catch (_) {}
      }
    } else {
      if (!kIsWeb) {
        try {
          await WakelockPlus.disable();
        } catch (_) {}
      }
      await _proximity.activateEarpieceProximity();
    }
  }

  Future<void> _disposeCallHardware() async {
    await _proximity.dispose();
    if (!kIsWeb) {
      try {
        await WakelockPlus.disable();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _session?.removeListener(_onSession);
    unawaited(_disposeCallHardware());
    super.dispose();
  }

  Future<void> _onLeavePressed() async {
    final s = _session;
    if (s == null) return;
    await s.hangUp();
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    final scheme = Theme.of(context).colorScheme;

    if (s == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final disconnected =
        s.connectionState.contains('Disconnected') &&
        s.phase == NativeLiveKitCallPhase.connected;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) return;
        NativeLiveKitCallHost.instance.markRouteVisible(false);
        NativeLiveKitCallHost.instance.markCallScreenRouteClosed();
        if (s.shouldAbortOnRoutePop) {
          unawaited(s.abortBecausePoppedDuringConnect());
        }
      },
      child: Scaffold(
        backgroundColor: MatrixTheme.terminalBackground,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).maybePop(),
            tooltip: 'Back',
          ),
          title: Text(
            s.title.toUpperCase(),
            style: TextStyle(fontFamily: MatrixTheme.fontFamily),
          ),
          backgroundColor: MatrixTheme.terminalBackground,
          foregroundColor: scheme.onSurface,
        ),
        body: _buildBody(context, s, scheme, disconnected),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    NativeLiveKitCallSession s,
    ColorScheme scheme,
    bool disconnected,
  ) {
    if (s.phase == NativeLiveKitCallPhase.connecting && s.error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (s.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '${s.error}',
            style: TextStyle(
              fontFamily: MatrixTheme.fontFamily,
              color: scheme.error,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (disconnected) {
      return Center(
        child: Text(
          'Disconnected',
          style: TextStyle(
            fontFamily: MatrixTheme.fontFamily,
            color: scheme.onSurface,
          ),
        ),
      );
    }

    if (s.phase == NativeLiveKitCallPhase.ended) {
      return const Center(child: SizedBox.shrink());
    }

    if (!s.preferVideoCallUi) {
      return _VoiceCallBody(
        session: s,
        scheme: scheme,
        onHangUp: _onLeavePressed,
      );
    }

    return _VideoCallBody(
      session: s,
      scheme: scheme,
      onHangUp: _onLeavePressed,
    );
  }
}

class _VoiceCallBody extends StatelessWidget {
  const _VoiceCallBody({
    required this.session,
    required this.scheme,
    required this.onHangUp,
  });

  final NativeLiveKitCallSession session;
  final ColorScheme scheme;
  final Future<void> Function() onHangUp;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final ringing =
            session.args.shouldPlayRingbackAndAloneTimeout &&
            session.remoteParticipantCount == 0;
        final status = ringing
            ? 'Ringing…'
            : (session.remoteParticipantCount > 0 ? 'Connected' : 'In call');

        return ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.call,
                      size: 88,
                      color: scheme.onSurface.withValues(alpha: 0.65),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      status,
                      style: TextStyle(
                        fontFamily: MatrixTheme.fontFamily,
                        fontSize: 18,
                        color: scheme.onSurface.withValues(alpha: 0.9),
                      ),
                    ),
                    if (!ringing) ...[
                      const SizedBox(height: 8),
                      Text(
                        session.callDurationEpochStarted
                            ? session.connectedCallDurationLabel
                            : session.connectionState,
                        style: TextStyle(
                          fontFamily: MatrixTheme.fontFamily,
                          fontSize: 12,
                          color: scheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 8),
                      Text(
                        'Waiting for others to join…',
                        style: TextStyle(
                          fontFamily: MatrixTheme.fontFamily,
                          fontSize: 12,
                          color: scheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                      child: CallMicActivityWaveform(
                        level: session.micCaptureLevel,
                        muted: session.micMuted,
                        height: 40,
                        activeColor: MatrixTheme.matrixLightGreen.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 32,
                child: _CallControlBar(session: session, onHangUp: onHangUp),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _VideoCallBody extends StatelessWidget {
  const _VideoCallBody({
    required this.session,
    required this.scheme,
    required this.onHangUp,
  });

  final NativeLiveKitCallSession session;
  final ColorScheme scheme;
  final Future<void> Function() onHangUp;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final cam = session.cameraController;
        final showLivePreview = session.hasLocalVideoPreview;
        final selfLabel =
            session.args.localDisplayName?.trim().isNotEmpty == true
            ? session.args.localDisplayName!.trim()
            : session.title;
        final placeholderSubtitle = showLivePreview
            ? ''
            : (session.cameraMuted
                  ? 'CAMERA OFF'
                  : (session.args.voiceOnly
                        ? 'AUDIO ONLY'
                        : 'NO CAMERA · AUDIO ONLY'));
        final ringing =
            session.args.shouldPlayRingbackAndAloneTimeout &&
            session.remoteParticipantCount == 0;

        return ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (showLivePreview && cam != null)
                Positioned.fill(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: cam.value.previewSize?.height ?? 480,
                      height: cam.value.previewSize?.width ?? 640,
                      child: CameraPreview(cam),
                    ),
                  ),
                )
              else
                Positioned.fill(
                  child: _LocalSelfVideoPlaceholder(
                    displayName: selfLabel,
                    avatarMxc: session.args.localAvatarMxc,
                    client: session.args.matrixClient,
                    scheme: scheme,
                    subtitle: placeholderSubtitle,
                  ),
                ),
              Positioned(
                left: 16,
                top: 16,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Text(
                      ringing
                          ? 'Calling…'
                          : (session.remoteParticipantCount > 0
                                ? (session.callDurationEpochStarted
                                      ? session.connectedCallDurationLabel
                                      : 'Connected')
                                : 'Waiting…'),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 96,
                child: CallMicActivityWaveform(
                  level: session.micCaptureLevel,
                  muted: session.micMuted,
                  height: 32,
                  activeColor: MatrixTheme.matrixLightGreen.withValues(alpha: 0.85),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 32,
                child: _CallControlBar(session: session, onHangUp: onHangUp),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CallControlBar extends StatelessWidget {
  const _CallControlBar({required this.session, required this.onHangUp});

  final NativeLiveKitCallSession session;
  final Future<void> Function() onHangUp;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final showCameraToggle =
            session.args.preferVideoCallUi || !session.args.voiceOnly;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _RoundCallButton(
              icon: session.micMuted ? Icons.mic_off : Icons.mic,
              label: session.micMuted ? 'Mic off' : 'Mic on',
              onPressed: () =>
                  unawaited(session.setMicrophoneMuted(!session.micMuted)),
              backgroundColor: session.micMuted
                  ? Colors.red.shade800
                  : Colors.white24,
            ),
            const SizedBox(width: 16),
            _RoundCallButton(
              icon: session.speakerOn ? Icons.volume_up : Icons.phone_in_talk,
              label: session.speakerOn ? 'Speaker' : 'Earpiece',
              onPressed: () =>
                  unawaited(session.setSpeakerOn(!session.speakerOn)),
              backgroundColor: session.speakerOn
                  ? Colors.teal.shade700
                  : Colors.white24,
            ),
            const SizedBox(width: 16),
            _RoundCallButton(
              icon: session.callHeld ? Icons.play_circle : Icons.pause_circle,
              label: session.callHeld ? 'Resume' : 'Hold',
              onPressed: () =>
                  unawaited(session.setCallHeld(!session.callHeld)),
              backgroundColor: session.callHeld
                  ? Colors.orange.shade800
                  : Colors.white24,
            ),
            if (showCameraToggle) ...[
              const SizedBox(width: 16),
              _RoundCallButton(
                icon: session.cameraMuted ? Icons.videocam_off : Icons.videocam,
                label: session.cameraMuted ? 'Cam off' : 'Cam on',
                onPressed: () =>
                    unawaited(session.setCameraMuted(!session.cameraMuted)),
                backgroundColor: session.cameraMuted
                    ? Colors.red.shade800
                    : Colors.white24,
              ),
            ],
            const SizedBox(width: 16),
            _RoundCallButton(
              icon: Icons.call_end,
              label: 'End',
              onPressed: () => unawaited(onHangUp()),
              backgroundColor: Colors.red.shade700,
            ),
          ],
        );
      },
    );
  }
}

String _initialsFromDisplayName(String name) {
  final t = name.trim();
  if (t.isEmpty) return '?';
  final parts = t.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.length >= 2) {
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
  if (t.length >= 2) {
    return t.substring(0, 2).toUpperCase();
  }
  return t[0].toUpperCase();
}

class _LocalSelfVideoPlaceholder extends StatefulWidget {
  const _LocalSelfVideoPlaceholder({
    required this.displayName,
    required this.avatarMxc,
    required this.client,
    required this.scheme,
    required this.subtitle,
  });

  final String displayName;
  final String? avatarMxc;
  final MatrixClient client;
  final ColorScheme scheme;
  final String subtitle;

  @override
  State<_LocalSelfVideoPlaceholder> createState() =>
      _LocalSelfVideoPlaceholderState();
}

class _LocalSelfVideoPlaceholderState
    extends State<_LocalSelfVideoPlaceholder> {
  Uint8List? _avatarBytes;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final mxc = widget.avatarMxc?.trim() ?? '';
    if (mxc.isEmpty) return;
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final b = await MatrixAvatarDiskCache.instance.loadOrFetch(mxc, () async {
        try {
          return await widget.client.fetchUserAvatarThumbnail(mxcUri: mxc);
        } catch (_) {
          return Uint8List(0);
        }
      });
      if (!mounted) return;
      setState(() {
        _avatarBytes = b.isEmpty ? null : b;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final initials = _initialsFromDisplayName(widget.displayName);
    final showPhoto = _avatarBytes != null && _avatarBytes!.isNotEmpty;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 56,
            backgroundColor: widget.scheme.primary.withValues(alpha: 0.22),
            backgroundImage: showPhoto ? MemoryImage(_avatarBytes!) : null,
            child: showPhoto
                ? null
                : (_loading
                      ? const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          initials,
                          style: TextStyle(
                            fontFamily: MatrixTheme.fontFamily,
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: widget.scheme.primary,
                          ),
                        )),
          ),
          const SizedBox(height: 16),
          Text(
            widget.displayName.toUpperCase(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: MatrixTheme.fontFamily,
              fontSize: 16,
              color: widget.scheme.onSurface.withValues(alpha: 0.9),
              letterSpacing: 1.2,
            ),
          ),
          if (widget.subtitle.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              widget.subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: MatrixTheme.fontFamily,
                fontSize: 11,
                letterSpacing: 0.8,
                color: widget.scheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RoundCallButton extends StatelessWidget {
  const _RoundCallButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.backgroundColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: backgroundColor,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }
}
