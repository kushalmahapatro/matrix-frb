import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/src/core/calls/call_history_store.dart';
import 'package:matrix/src/core/calls/incoming_call_banner_controller.dart';
import 'package:matrix/src/core/calls/matrix_call_kit_coordinator.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';
import 'package:matrix/src/theme/matrix_theme.dart';

/// Full-screen accept / decline for an incoming MatrixRTC ring (opened from the incoming banner).
class MatrixIncomingCallAnswerScreen extends StatefulWidget {
  const MatrixIncomingCallAnswerScreen({
    super.key,
    required this.pending,
  });

  final PendingIncomingCallRing pending;

  @override
  State<MatrixIncomingCallAnswerScreen> createState() =>
      _MatrixIncomingCallAnswerScreenState();
}

class _MatrixIncomingCallAnswerScreenState
    extends State<MatrixIncomingCallAnswerScreen> {
  Timer? _timer;
  late int _secondsLeft;

  @override
  void initState() {
    super.initState();
    IncomingCallBannerController.instance.setIncomingAnswerRouteActive(true);
    IncomingCallBannerController.instance.pauseAutoDeclineTimer();
    _secondsLeft = 30;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _secondsLeft -= 1);
      if (_secondsLeft <= 0) {
        _timer?.cancel();
        _reject('Missed call');
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    // Avoid notifying [IncomingCallBannerController] listeners during unmount:
    // the framework locks the tree and [ListenableBuilder] cannot rebuild yet.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctrl = IncomingCallBannerController.instance;
      ctrl.setIncomingAnswerRouteActive(false);
      ctrl.resumeAutoDeclineIfStillPending();
    });
    super.dispose();
  }

  /// Back / close: return to the banner only; does not decline the call.
  void _popWithoutDeclining() {
    _timer?.cancel();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _acceptVoiceOnly() async {
    await _acceptJoin(
      voiceOnly: true,
      preferVideoCallUi: false,
    );
  }

  /// Join with microphone only (no camera track), using the video-style in-call shell.
  Future<void> _acceptVoiceVideoShell() async {
    await _acceptJoin(
      voiceOnly: true,
      preferVideoCallUi: true,
    );
  }

  /// Join with camera + microphone when the callee wants full video.
  Future<void> _acceptWithVideo() async {
    await _acceptJoin(
      voiceOnly: false,
      preferVideoCallUi: true,
    );
  }

  Future<void> _acceptJoin({
    required bool voiceOnly,
    required bool preferVideoCallUi,
  }) async {
    _timer?.cancel();
    final p = widget.pending;
    IncomingCallBannerController.instance.dismiss();
    await MatrixCallKitCoordinator.instance.endCallKitIncomingIfStored(
      p.callKitId,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    final client = MatrixService().client;
    unawaited(
      MatrixCallKitCoordinator.instance.openAcceptedIncomingNativeLiveKit(
        client: client,
        roomId: p.roomId,
        roomName: p.roomName,
        voiceOnly: voiceOnly,
        preferVideoCallUi: preferVideoCallUi,
      ),
    );
  }

  Future<void> _reject(String reason) async {
    _timer?.cancel();
    final p = widget.pending;
    IncomingCallBannerController.instance.dismiss();
    await MatrixCallKitCoordinator.instance.endCallKitIncomingIfStored(
      p.callKitId,
    );
    if (p.roomId.isNotEmpty && p.rtcEventId.isNotEmpty) {
      try {
        await MatrixService().client.declineRtcCall(
          roomId: p.roomId,
          rtcNotificationEventId: p.rtcEventId,
        );
      } catch (e, st) {
        debugPrint('MatrixIncomingCallAnswerScreen decline: $e\n$st');
      }
    }
    if (p.roomId.isNotEmpty) {
      unawaited(
        CallHistoryStore.instance.appendIncomingCallOutcome(
          roomId: p.roomId,
          roomName: p.roomName,
          isDirectRoom: false,
          voiceOnly: true,
          endReason: reason,
        ),
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = widget.pending;
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    return Scaffold(
      backgroundColor: MatrixTheme.terminalBackground,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _popWithoutDeclining,
          tooltip: 'Back to banner',
        ),
        title: Text(
          'INCOMING CALL',
          style: TextStyle(fontFamily: MatrixTheme.fontFamily),
        ),
        backgroundColor: MatrixTheme.terminalBackground,
        foregroundColor: scheme.onSurface,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: landscape
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 5,
                      child: _IncomingCallHeader(
                        scheme: scheme,
                        p: p,
                        secondsLeft: _secondsLeft,
                        compact: true,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      flex: 4,
                      child: _IncomingCallActionsColumn(
                        scheme: scheme,
                        onDecline: () => unawaited(_reject('Declined')),
                        onVoice: () => unawaited(_acceptVoiceOnly()),
                        onVoiceNoCamUi:
                            () => unawaited(_acceptVoiceVideoShell()),
                        onVideo: () => unawaited(_acceptWithVideo()),
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    const Spacer(flex: 2),
                    _IncomingCallHeader(
                      scheme: scheme,
                      p: p,
                      secondsLeft: _secondsLeft,
                      compact: false,
                    ),
                    const Spacer(flex: 2),
                    _IncomingCallActionsColumn(
                      scheme: scheme,
                      onDecline: () => unawaited(_reject('Declined')),
                      onVoice: () => unawaited(_acceptVoiceOnly()),
                      onVoiceNoCamUi:
                          () => unawaited(_acceptVoiceVideoShell()),
                      onVideo: () => unawaited(_acceptWithVideo()),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
        ),
      ),
    );
  }
}

class _IncomingCallHeader extends StatelessWidget {
  const _IncomingCallHeader({
    required this.scheme,
    required this.p,
    required this.secondsLeft,
    required this.compact,
  });

  final ColorScheme scheme;
  final PendingIncomingCallRing p;
  final int secondsLeft;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 56.0 : 72.0;
    final titleSize = compact ? 18.0 : 22.0;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.call_received,
          size: iconSize,
          color: scheme.primary.withValues(alpha: 0.85),
        ),
        SizedBox(height: compact ? 12 : 24),
        Text(
          p.callerLabel.toUpperCase(),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: MatrixTheme.fontFamily,
            fontSize: titleSize,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          p.roomName,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: MatrixTheme.fontFamily,
            fontSize: compact ? 12 : 14,
            color: scheme.onSurface.withValues(alpha: 0.65),
          ),
        ),
        SizedBox(height: compact ? 12 : 28),
        Text(
          'Choose how to join',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: MatrixTheme.fontFamily,
            fontSize: compact ? 11 : 12,
            color: scheme.onSurface.withValues(alpha: 0.45),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Auto-decline in $secondsLeft s',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: MatrixTheme.fontFamily,
            fontSize: compact ? 11 : 13,
            color: scheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}

class _IncomingCallActionsColumn extends StatelessWidget {
  const _IncomingCallActionsColumn({
    required this.scheme,
    required this.onDecline,
    required this.onVoice,
    required this.onVoiceNoCamUi,
    required this.onVideo,
  });

  final ColorScheme scheme;
  final VoidCallback onDecline;
  final VoidCallback onVoice;
  final VoidCallback onVoiceNoCamUi;
  final VoidCallback onVideo;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.tonalIcon(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          onPressed: onVoice,
          icon: const Icon(Icons.mic),
          label: Text(
            'Voice only',
            style: TextStyle(fontFamily: MatrixTheme.fontFamily),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          onPressed: onVoiceNoCamUi,
          icon: const Icon(Icons.videocam_off_outlined),
          label: Text(
            'Video UI · mic only',
            style: TextStyle(fontFamily: MatrixTheme.fontFamily),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary,
          ),
          onPressed: onVideo,
          icon: const Icon(Icons.videocam),
          label: Text(
            'Video + voice',
            style: TextStyle(fontFamily: MatrixTheme.fontFamily),
          ),
        ),
        const SizedBox(height: 14),
        TextButton(
          onPressed: onDecline,
          child: Text(
            'Decline',
            style: TextStyle(
              fontFamily: MatrixTheme.fontFamily,
              color: scheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}
