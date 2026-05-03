// ignore_for_file: experimental_member_use

import 'dart:io' show Platform;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:matrix/src/core/calls/native_livekit_call_session.dart';
import 'package:matrix/src/theme/matrix_theme.dart';

/// Full audio output picker (speaker, phone, wired / Bluetooth when exposed by the OS).
Future<void> showCallAudioOutputSheet(
  BuildContext context,
  NativeLiveKitCallSession session,
) async {
  if (kIsWeb) return;
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _CallAudioOutputSheetBody(session: session),
  );
}

class _CallAudioOutputSheetBody extends StatefulWidget {
  const _CallAudioOutputSheetBody({required this.session});

  final NativeLiveKitCallSession session;

  @override
  State<_CallAudioOutputSheetBody> createState() => _CallAudioOutputSheetBodyState();
}

class _CallAudioOutputSheetBodyState extends State<_CallAudioOutputSheetBody> {
  late Future<List<AudioDevice>> _externalsFuture;

  NativeLiveKitCallSession get session => widget.session;

  @override
  void initState() {
    super.initState();
    _externalsFuture = session.fetchSelectableAudioOutputs();
    session.addListener(_onSession);
  }

  @override
  void dispose() {
    session.removeListener(_onSession);
    super.dispose();
  }

  void _onSession() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                'AUDIO OUTPUT',
                style: TextStyle(
                  fontFamily: MatrixTheme.fontFamily,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  fontSize: 13,
                  color: scheme.onSurface.withValues(alpha: 0.75),
                ),
              ),
            ),
            FutureBuilder<List<AudioDevice>>(
              future: _externalsFuture,
              builder: (context, snap) {
                final externals = snap.data ?? const <AudioDevice>[];
                return ListView(
                  shrinkWrap: true,
                  physics: const ClampingScrollPhysics(),
                  children: [
                    ListTile(
                      leading: Icon(
                        session.speakerOn ? Icons.check_circle : Icons.circle_outlined,
                        color: session.speakerOn ? scheme.primary : null,
                      ),
                      title: Text(
                        'Speaker',
                        style: TextStyle(fontFamily: MatrixTheme.fontFamily),
                      ),
                      subtitle: Text(
                        'Loudspeaker',
                        style: TextStyle(fontFamily: MatrixTheme.fontFamily),
                      ),
                      onTap: () async {
                        await session.pickCallAudioOutputSpeaker();
                        if (context.mounted) Navigator.of(context).pop();
                      },
                    ),
                    ListTile(
                      leading: Icon(
                        session.audioRouteIsBuiltInEarpiecePath
                            ? Icons.check_circle
                            : Icons.circle_outlined,
                        color: session.audioRouteIsBuiltInEarpiecePath ? scheme.primary : null,
                      ),
                      title: Text(
                        'Phone',
                        style: TextStyle(fontFamily: MatrixTheme.fontFamily),
                      ),
                      subtitle: Text(
                        'Receiver / system default',
                        style: TextStyle(fontFamily: MatrixTheme.fontFamily),
                      ),
                      onTap: () async {
                        await session.pickCallAudioOutputPhone();
                        if (context.mounted) Navigator.of(context).pop();
                      },
                    ),
                    if (externals.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(
                          'Headsets & accessories',
                          style: TextStyle(
                            fontFamily: MatrixTheme.fontFamily,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface.withValues(alpha: 0.55),
                          ),
                        ),
                      ),
                      for (final d in externals)
                        ListTile(
                          leading: Icon(
                            !session.speakerOn &&
                                    session.audioRouteActiveOutputDeviceId == d.id
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                            color: !session.speakerOn &&
                                    session.audioRouteActiveOutputDeviceId == d.id
                                ? scheme.primary
                                : null,
                          ),
                          title: Text(
                            d.name.trim().isEmpty ? _fallbackName(d.type) : d.name,
                            style: TextStyle(fontFamily: MatrixTheme.fontFamily),
                          ),
                          subtitle: Text(
                            _subtitleForType(d.type),
                            style: TextStyle(fontFamily: MatrixTheme.fontFamily),
                          ),
                          onTap: () async {
                            final ok = await session.pickCallAudioOutputExternal(d);
                            if (!context.mounted) return;
                            if (!ok && Platform.isAndroid) {
                              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Could not switch to "${d.name}". '
                                    'This path needs Android 12+ on some devices.',
                                    style: TextStyle(
                                      fontFamily: MatrixTheme.fontFamily,
                                    ),
                                  ),
                                ),
                              );
                            }
                            if (context.mounted) Navigator.of(context).pop();
                          },
                        ),
                    ],
                    if (defaultTargetPlatform == TargetPlatform.iOS)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Text(
                          'On iOS, Bluetooth routing is managed by the system. '
                          'Choose Phone for the receiver, or a listed headset when shown.',
                          style: TextStyle(
                            fontFamily: MatrixTheme.fontFamily,
                            fontSize: 11,
                            height: 1.35,
                            color: scheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

String _fallbackName(AudioDeviceType t) {
  switch (t) {
    case AudioDeviceType.bluetoothA2dp:
    case AudioDeviceType.bluetoothSco:
    case AudioDeviceType.bluetoothLe:
      return 'Bluetooth';
    case AudioDeviceType.wiredHeadphones:
      return 'Headphones';
    case AudioDeviceType.wiredHeadset:
    case AudioDeviceType.headsetMic:
      return 'Headset';
    case AudioDeviceType.usbAudio:
      return 'USB audio';
    default:
      return 'Audio device';
  }
}

String _subtitleForType(AudioDeviceType t) {
  switch (t) {
    case AudioDeviceType.bluetoothA2dp:
    case AudioDeviceType.bluetoothSco:
    case AudioDeviceType.bluetoothLe:
      return 'Bluetooth';
    case AudioDeviceType.wiredHeadphones:
    case AudioDeviceType.wiredHeadset:
    case AudioDeviceType.headsetMic:
      return 'Wired';
    case AudioDeviceType.usbAudio:
      return 'USB';
    default:
      return 'External';
  }
}
