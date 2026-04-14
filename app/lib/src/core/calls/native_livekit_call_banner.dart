import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:matrix/src/core/calls/native_livekit_call_host.dart';
import 'package:matrix/src/core/calls/native_livekit_call_session.dart';
import 'package:matrix/src/core/calls/matrix_call_screen_route.dart';
import 'package:matrix/src/core/desktop/desktop_ongoing_call_window_opener.dart';
import 'package:matrix/src/core/desktop/desktop_ui_helpers.dart';
import 'package:matrix/src/core/navigation/app_navigation.dart';
import 'package:matrix/src/theme/matrix_theme.dart';
import 'package:matrix/src/theme/theme_provider.dart';
import 'package:provider/provider.dart';

Future<void> openNativeLiveKitCallFullScreenRoute() async {
  final nav = AppNavigation.rootNavigatorKey.currentState;
  if (nav == null || !nav.mounted) return;
  NativeLiveKitCallHost.instance.markRouteVisible(true);
  NativeLiveKitCallHost.instance.markCallScreenRouteOpening();
  try {
    await nav.push<void>(matrixNativeLiveKitCallRoute());
  } finally {
    NativeLiveKitCallHost.instance.markCallScreenRouteClosed();
  }
}

/// Desktop: focuses or recreates the auxiliary call window. Other platforms: full-screen route.
Future<void> openNativeLiveKitCallUiFromBanner(BuildContext context) async {
  final session = NativeLiveKitCallHost.instance.session;
  if (session == null) return;
  if (!kIsWeb && isDesktopTargetPlatform()) {
    final isDark = Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
    await DesktopOngoingCallWindowOpener.focusOrEnsureActiveCallWindow(
      session: session,
      isDarkMode: isDark,
    );
    return;
  }
  await openNativeLiveKitCallFullScreenRoute();
}

/// Optional draggable video PiP while the call UI route is not visible. The call
/// strip is shown under the route [AppBar] via [NativeLiveKitMinimizedCallAppBarBottom].
class NativeLiveKitMinimizedCallOverlay extends StatefulWidget {
  const NativeLiveKitMinimizedCallOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<NativeLiveKitMinimizedCallOverlay> createState() =>
      _NativeLiveKitMinimizedCallOverlayState();
}

class _NativeLiveKitMinimizedCallOverlayState
    extends State<NativeLiveKitMinimizedCallOverlay> {
  /// Drag delta from the default PiP anchor (below app bar + call banner).
  Offset _pipDragOffset = Offset.zero;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: NativeLiveKitCallHost.instance,
      builder: (context, _) {
        final host = NativeLiveKitCallHost.instance;
        final session = host.session;
        if (host.showMinimizedChrome && session != null) {
          return ListenableBuilder(
            listenable: session,
            builder: (ctx, _) {
              return _minimizedStack(ctx, session);
            },
          );
        }
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [widget.child],
        );
      },
    );
  }

  Widget _minimizedStack(
    BuildContext context,
    NativeLiveKitCallSession session,
  ) {
    final mq = MediaQuery.of(context);
    final toolbarHeight =
        Theme.of(context).appBarTheme.toolbarHeight ?? kToolbarHeight;
    // Banner lives in each route’s [AppBar.bottom]; anchor PiP under app bar + banner.
    final belowAppChrome =
        mq.padding.top +
        toolbarHeight +
        NativeLiveKitMinimizedCallAppBarBottom.kHeight;
    final pipAnchorTop = belowAppChrome + 8;

    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        widget.child,
        if (session.showMinimizedVideoPip)
          Positioned(
            left: 16 + _pipDragOffset.dx,
            top: pipAnchorTop + _pipDragOffset.dy,
            child: _DraggableVideoPip(
              session: session,
              onPanDelta: (d) {
                setState(() => _pipDragOffset += d);
              },
            ),
          ),
      ],
    );
  }
}

/// Minimized LiveKit call strip for [AppBar.bottom]. Reserves layout space so the
/// scaffold body sits below the banner (no overlap).
class NativeLiveKitMinimizedCallAppBarBottom extends StatelessWidget
    implements PreferredSizeWidget {
  const NativeLiveKitMinimizedCallAppBarBottom({
    super.key,
    required this.session,
    required this.onOpen,
    required this.onHangUp,
  });

  /// Keep in sync with banner padding/content; used by the global PiP overlay.
  static const double kHeight = 76;

  final NativeLiveKitCallSession session;
  final VoidCallback onOpen;
  final VoidCallback onHangUp;

  @override
  Size get preferredSize => const Size.fromHeight(kHeight);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        return _CallBanner(
          session: session,
          onOpen: onOpen,
          onHangUp: onHangUp,
        );
      },
    );
  }
}

class _CallBanner extends StatelessWidget {
  const _CallBanner({
    required this.session,
    required this.onOpen,
    required this.onHangUp,
  });

  final NativeLiveKitCallSession session;
  final VoidCallback onOpen;
  final VoidCallback onHangUp;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final voiceHint = session.preferVideoCallUi ? 'Video call' : 'Voice call';
    final durationOrStatus = session.phase == NativeLiveKitCallPhase.connecting
        ? 'Connecting…'
        : (session.remoteParticipantCount > 0
              ? (session.connectedCallDurationLabel.isNotEmpty
                    ? session.connectedCallDurationLabel
                    : '0:00')
              : 'Waiting for others…');

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.95),
        border: Border(
          bottom: BorderSide(color: scheme.outline.withValues(alpha: 0.35)),
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          top: false,
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: InkWell(
                    onTap: onOpen,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 5,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            session.preferVideoCallUi
                                ? Icons.videocam
                                : Icons.call,
                            size: 20,
                            color: scheme.onPrimaryContainer.withValues(
                              alpha: 0.7,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  session.title.toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: MatrixTheme.fontFamily,
                                    fontWeight: FontWeight.w700,
                                    color: scheme.onPrimaryContainer,
                                    fontSize: 15,
                                    height: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  durationOrStatus,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: MatrixTheme.fontFamily,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.6,
                                    color: scheme.onPrimaryContainer.withValues(
                                      alpha: 0.92,
                                    ),
                                  ),
                                ),
                                if (!session.preferVideoCallUi) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    voiceHint,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: MatrixTheme.fontFamily,
                                      fontSize: 10,
                                      color: scheme.onPrimaryContainer
                                          .withValues(alpha: 0.45),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Icon(
                            Icons.open_in_full,
                            size: 20,
                            color: scheme.onPrimaryContainer.withValues(
                              alpha: 0.75,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: session.micMuted
                      ? 'Unmute microphone'
                      : 'Mute microphone',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  icon: Icon(
                    session.micMuted ? Icons.mic_off : Icons.mic,
                    size: 22,
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.9),
                  ),
                  onPressed: () =>
                      unawaited(session.setMicrophoneMuted(!session.micMuted)),
                ),
                IconButton(
                  tooltip: session.speakerOn ? 'Speaker on' : 'Earpiece',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  icon: Icon(
                    session.speakerOn ? Icons.volume_up : Icons.phone_android,
                    size: 22,
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.9),
                  ),
                  onPressed: () =>
                      unawaited(session.setSpeakerOn(!session.speakerOn)),
                ),
                if (session.preferVideoCallUi)
                  IconButton(
                    tooltip: session.cameraMuted
                        ? 'Turn camera on'
                        : 'Turn camera off',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    icon: Icon(
                      session.cameraMuted ? Icons.videocam_off : Icons.videocam,
                      size: 22,
                      color: scheme.onPrimaryContainer.withValues(alpha: 0.9),
                    ),
                    onPressed: () =>
                        unawaited(session.setCameraMuted(!session.cameraMuted)),
                  ),
                Semantics(
                  label: 'End call',
                  button: true,
                  child: InkWell(
                    onTap: onHangUp,
                    customBorder: const CircleBorder(),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Icon(
                        Icons.call_end,
                        size: 22,
                        color: scheme.error,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DraggableVideoPip extends StatelessWidget {
  const _DraggableVideoPip({required this.session, required this.onPanDelta});

  final NativeLiveKitCallSession session;
  final void Function(Offset delta) onPanDelta;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final cam = session.cameraController;
        final ready = cam != null && cam.value.isInitialized;

        return GestureDetector(
          onTap: () {
            if (!kIsWeb && isDesktopTargetPlatform()) {
              unawaited(openNativeLiveKitCallUiFromBanner(context));
              return;
            }
            final nav = AppNavigation.rootNavigatorKey.currentState;
            if (nav == null || !nav.mounted) return;
            NativeLiveKitCallHost.instance.markRouteVisible(true);
            NativeLiveKitCallHost.instance.markCallScreenRouteOpening();
            unawaited(
              nav
                  .push<void>(matrixNativeLiveKitCallRoute())
                  .whenComplete(
                    NativeLiveKitCallHost.instance.markCallScreenRouteClosed,
                  ),
            );
          },
          onPanUpdate: (d) => onPanDelta(d.delta),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: 112,
              height: 148,
              child: ready
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CameraPreview(cam),
                    )
                  : const ColoredBox(
                      color: Colors.black,
                      child: Center(
                        child: Icon(Icons.videocam_off, color: Colors.white54),
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
}
