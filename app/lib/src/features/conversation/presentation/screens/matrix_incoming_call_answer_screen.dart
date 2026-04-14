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
    IncomingCallBannerController.instance.setIncomingAnswerRouteActive(false);
    IncomingCallBannerController.instance.resumeAutoDeclineIfStillPending();
    super.dispose();
  }

  /// Back / close: return to the banner only; does not decline the call.
  void _popWithoutDeclining() {
    _timer?.cancel();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _accept() async {
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
          child: Column(
            children: [
              const Spacer(flex: 2),
              Icon(
                Icons.call_received,
                size: 72,
                color: scheme.primary.withValues(alpha: 0.85),
              ),
              const SizedBox(height: 24),
              Text(
                p.callerLabel.toUpperCase(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: MatrixTheme.fontFamily,
                  fontSize: 22,
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
                  fontSize: 14,
                  color: scheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Auto-decline in $_secondsLeft s',
                style: TextStyle(
                  fontFamily: MatrixTheme.fontFamily,
                  fontSize: 13,
                  color: scheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              const Spacer(flex: 3),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => unawaited(_reject('Declined')),
                      child: Text(
                        'Decline',
                        style: TextStyle(
                          fontFamily: MatrixTheme.fontFamily,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: scheme.primary,
                        foregroundColor: scheme.onPrimary,
                      ),
                      onPressed: () => unawaited(_accept()),
                      icon: const Icon(Icons.call),
                      label: Text(
                        'Accept',
                        style: TextStyle(fontFamily: MatrixTheme.fontFamily),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
