import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/src/core/calls/livekit_token_service.dart';
import 'package:matrix/src/core/permissions/app_runtime_permissions.dart';
import 'package:matrix/src/core/domain/services/app_config.dart';
import 'package:matrix/src/core/navigation/app_navigation.dart';
import 'package:matrix/src/core/network/network_availability.dart';
import 'package:matrix/src/core/calls/matrix_call_screen_route.dart';
import 'package:matrix/src/core/calls/native_livekit_call_host.dart';
import 'package:matrix/src/core/calls/native_livekit_call_session.dart';
import 'package:matrix/src/core/desktop/desktop_ui_helpers.dart';
import 'package:matrix/src/features/settings/domain/profile_prefs.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';
import 'package:provider/provider.dart';

void _showOfflineSnack(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('No network connection. Calls need internet.'),
    ),
  );
}

void _showNativeCallSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Bottom sheet: voice / video / join active call — **native LiveKit only** (Rust + Flutter capture).
Future<void> showMatrixCallOptionsSheet({
  required BuildContext context,
  required String roomId,
  required String roomName,
  required bool isDirectRoom,
}) async {
  if (!context.mounted) return;
  final online = context.read<NetworkAvailability>().isOnline;
  if (!online) {
    _showOfflineSnack(context);
    return;
  }

  final client = MatrixService().client;
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetCtx) {
      return SafeArea(
        child: FutureBuilder<bool>(
          future: client.roomHasActiveCall(roomId: roomId),
          builder: (ctx, snap) {
            final waiting = snap.connectionState == ConnectionState.waiting;
            final hasActive = snap.data == true;
            final subtitle = isDirectRoom ? 'Direct message' : 'Group room';

            Future<void> startCall({
              required bool userPickedVoiceOnly,
              required bool joinExisting,
            }) async {
              final micOk =
                  await AppRuntimePermissions.ensureMicrophoneForVoiceCall(
                    context,
                  );
              if (!micOk) return;
              if (!context.mounted) return;

              final preferVideoCallUi = !userPickedVoiceOnly;
              var liveKitVoiceOnly = userPickedVoiceOnly;
              if (!userPickedVoiceOnly) {
                final camOk = await AppRuntimePermissions.ensureCamera(
                  context,
                  title: 'Camera',
                  rationale:
                      'Allow camera to share video, or decline and join with microphone only.',
                );
                if (!camOk) {
                  liveKitVoiceOnly = true;
                }
              }

              if (!sheetCtx.mounted) return;
              Navigator.of(sheetCtx).pop();
              if (!context.mounted) return;
              if (!context.read<NetworkAvailability>().isOnline) {
                _showOfflineSnack(context);
                return;
              }

              if (!AppConfig.isNativeLiveKitConfigurable) {
                if (context.mounted) {
                  _showNativeCallSnack(
                    context,
                    'LiveKit is not configured. Set LIVEKIT_URL and '
                    'LIVEKIT_TOKEN_API_URL (or dev token / legacy fetch URL) in dart defines.',
                  );
                }
                return;
              }

              try {
                final creds = await LiveKitTokenService.resolve(
                  matrixClient: client,
                  matrixRoomId: roomId,
                  voiceOnly: liveKitVoiceOnly,
                  joinExisting: joinExisting,
                );
                if (!context.mounted) return;
                if (creds == null) {
                  _showNativeCallSnack(
                    context,
                    'Could not get a LiveKit token. Check your token service and LIVEKIT_URL.',
                  );
                  return;
                }
                String? rtcNotificationId;
                if (!joinExisting) {
                  try {
                    rtcNotificationId = await client.sendRtcRingNotification(
                      roomId: roomId,
                      voiceOnly: liveKitVoiceOnly,
                    );
                  } catch (e, st) {
                    debugPrint('sendRtcRingNotification failed: $e\n$st');
                    if (context.mounted) {
                      _showNativeCallSnack(
                        context,
                        'Could not ring the other person’s devices (Matrix signaling). '
                        'Check network, room membership, and that MatrixRTC is supported on your server.',
                      );
                    }
                    return;
                  }
                }
                if (!context.mounted) return;
                await NativeLiveKitCallHost.instance.prepareForNewCall();
                if (!context.mounted) return;
                String? localDisplayName;
                try {
                  final n = await client.getDisplayName();
                  if (n != null && n.trim().isNotEmpty) {
                    localDisplayName = n.trim();
                  }
                } catch (_) {}
                final session = NativeLiveKitCallSession(
                  NativeLiveKitCallArgs(
                    matrixClient: client,
                    livekitUrl: creds.url,
                    accessToken: creds.token,
                    title: roomName,
                    matrixRoomId: roomId,
                    voiceOnly: liveKitVoiceOnly,
                    preferVideoCallUi: preferVideoCallUi,
                    localDisplayName: localDisplayName,
                    localAvatarMxc: ProfilePrefs.instance.ownAvatarMxc,
                    isDirectRoom: isDirectRoom,
                    joinedExisting: joinExisting,
                    rtcNotificationEventId: rtcNotificationId,
                  ),
                );
                if (isDesktopTargetPlatform()) {
                  NativeLiveKitCallHost.instance.beginCallDesktopDetached(
                    session,
                  );
                  // Without pushing [NativeLiveKitCallScreen], nothing calls [ensureStarted].
                  await session.ensureStarted();
                  return;
                }
                NativeLiveKitCallHost.instance.beginCall(session);
                final nav = AppNavigation.rootNavigatorKey.currentState;
                if (nav == null || !nav.mounted) return;
                NativeLiveKitCallHost.instance.markCallScreenRouteOpening();
                try {
                  await nav.push<void>(matrixNativeLiveKitCallRoute());
                } finally {
                  NativeLiveKitCallHost.instance.markCallScreenRouteClosed();
                }
              } catch (e, st) {
                debugPrint('Native LiveKit call failed: $e\n$st');
                if (context.mounted) {
                  _showNativeCallSnack(context, 'Call failed: $e');
                }
              }
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    title: Text(
                      'Call',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(subtitle),
                  ),
                  if (waiting)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...[
                    ListTile(
                      leading: Icon(
                        Icons.videocam_outlined,
                        color: scheme.primary,
                      ),
                      title: const Text('Video call'),
                      subtitle: const Text(
                        'Start a new video call in this room',
                      ),
                      onTap: () => unawaited(
                        startCall(
                          userPickedVoiceOnly: false,
                          joinExisting: false,
                        ),
                      ),
                    ),
                    ListTile(
                      leading: Icon(Icons.call_outlined, color: scheme.primary),
                      title: const Text('Voice call'),
                      subtitle: const Text('Start a voice-only call'),
                      onTap: () => unawaited(
                        startCall(
                          userPickedVoiceOnly: true,
                          joinExisting: false,
                        ),
                      ),
                    ),
                    if (hasActive)
                      ListTile(
                        leading: Icon(
                          Icons.groups_outlined,
                          color: scheme.tertiary,
                        ),
                        title: const Text('Join active call'),
                        subtitle: const Text(
                          'Someone may already be in this room’s call',
                        ),
                        onTap: () => unawaited(
                          startCall(
                            userPickedVoiceOnly: false,
                            joinExisting: true,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            );
          },
        ),
      );
    },
  );
}
