import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/src/core/calls/incoming_call_banner_controller.dart';
import 'package:matrix/src/core/calls/matrix_call_screen_route.dart';
import 'package:matrix/src/core/navigation/app_navigation.dart';
import 'package:matrix/src/features/conversation/presentation/screens/matrix_incoming_call_answer_screen.dart';
import 'package:matrix/src/theme/matrix_theme.dart';

/// Non-blocking strip when a MatrixRTC ring arrives; tap opens [MatrixIncomingCallAnswerScreen].
///
/// Sits above app content and below [NativeLiveKitMinimizedCallOverlay] so an ongoing call banner stays on top.
class IncomingCallBannerOverlay extends StatelessWidget {
  const IncomingCallBannerOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: IncomingCallBannerController.instance,
      builder: (context, _) {
        final ctrl = IncomingCallBannerController.instance;
        final pending = ctrl.pending;
        if (!ctrl.shouldShowIncomingStrip || pending == null) {
          return child;
        }
        final mq = MediaQuery.of(context);
        final toolbarHeight =
            Theme.of(context).appBarTheme.toolbarHeight ?? kToolbarHeight;
        final top = mq.padding.top + toolbarHeight;

        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            child,
            Positioned(
              left: 0,
              right: 0,
              top: top,
              child: Material(
                color: Colors.transparent,
                child: _IncomingCallStrip(
                  pending: pending,
                  onOpenAnswerScreen: () => unawaited(_openAnswer(pending)),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openAnswer(PendingIncomingCallRing pending) async {
    final ctrl = IncomingCallBannerController.instance;
    if (ctrl.incomingAnswerRouteActive) return;
    ctrl.setIncomingAnswerRouteActive(true);
    final nav = AppNavigation.rootNavigatorKey.currentState;
    if (nav == null || !nav.mounted) {
      ctrl.setIncomingAnswerRouteActive(false);
      return;
    }
    try {
      await nav.push<void>(
        matrixIncomingAnswerRoute(
          MatrixIncomingCallAnswerScreen(pending: pending),
        ),
      );
    } catch (e, st) {
      debugPrint('IncomingCallBannerOverlay push answer screen: $e\n$st');
      ctrl.setIncomingAnswerRouteActive(false);
    }
  }
}

class _IncomingCallStrip extends StatelessWidget {
  const _IncomingCallStrip({
    required this.pending,
    required this.onOpenAnswerScreen,
  });

  final PendingIncomingCallRing pending;
  final VoidCallback onOpenAnswerScreen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.98),
        border: Border(
          bottom: BorderSide(color: scheme.outline.withValues(alpha: 0.35)),
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          top: false,
          bottom: false,
          child: InkWell(
            onTap: onOpenAnswerScreen,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.phone_callback,
                    size: 22,
                    color: scheme.onTertiaryContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'INCOMING CALL',
                          style: TextStyle(
                            fontFamily: MatrixTheme.fontFamily,
                            fontSize: 10,
                            letterSpacing: 0.8,
                            color: scheme.onTertiaryContainer
                                .withValues(alpha: 0.75),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          pending.callerLabel.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: MatrixTheme.fontFamily,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: scheme.onTertiaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: scheme.onTertiaryContainer.withValues(alpha: 0.8),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
