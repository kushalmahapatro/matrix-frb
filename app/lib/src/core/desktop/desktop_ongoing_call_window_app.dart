import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:matrix/src/core/desktop/desktop_auxiliary_window_channel.dart';
import 'package:matrix/src/core/desktop/desktop_compact_call_window_position.dart';
import 'package:matrix/src/core/desktop/desktop_compact_call_window_size.dart';
import 'package:matrix/src/core/desktop/desktop_ongoing_call_main_bridge.dart';
import 'package:matrix/src/core/desktop/desktop_ui_helpers.dart';
import 'package:matrix/src/core/calls/call_mic_activity_waveform.dart';
import 'package:matrix/src/core/desktop/desktop_window_args.dart';
import 'package:matrix/src/theme/matrix_theme.dart';
import 'package:window_manager/window_manager.dart';

Future<void> runDesktopOngoingCallWindowApp(
  DesktopOngoingCallWindowArgs args,
) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (isDesktopTargetPlatform()) {
    try {
      await windowManager.ensureInitialized();
      await registerDesktopAuxiliaryWindowControllerHandlers();
      await windowManager.waitUntilReadyToShow(
        WindowOptions(
          size: DesktopCompactCallWindowSize.logicalSize,
          center: false,
          backgroundColor: Colors.transparent,
          skipTaskbar: false,
          title: _ongoingCallNativeWindowTitle(args),
        ),
        () async {
          await positionDesktopCompactCallWindowBottomRight();
          await windowManager.show();
          await windowManager.focus();
        },
      );
    } catch (e, st) {
      debugPrint('runDesktopOngoingCallWindowApp window_manager: $e\n$st');
    }
  }

  runApp(_OngoingCallWindowRoot(args: args));
}

String _ongoingCallNativeWindowTitle(DesktopOngoingCallWindowArgs args) {
  if (args.roomId.isNotEmpty) {
    return 'Call · ${args.roomId}';
  }
  if (args.title.isNotEmpty) return args.title;
  return 'Matrix call';
}

class _OngoingCallWindowRoot extends StatelessWidget {
  const _OngoingCallWindowRoot({required this.args});

  final DesktopOngoingCallWindowArgs args;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: MatrixTheme.getTheme(args.isDarkMode, useDesktopChrome: true),
      home: _OngoingCallScaffold(args: args),
    );
  }
}

class _OngoingCallScaffold extends StatefulWidget {
  const _OngoingCallScaffold({required this.args});

  final DesktopOngoingCallWindowArgs args;

  @override
  State<_OngoingCallScaffold> createState() => _OngoingCallScaffoldState();
}

class _OngoingCallScaffoldState extends State<_OngoingCallScaffold> {
  Timer? _poll;
  Map<String, dynamic>? _snap;
  bool _closeRequested = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _poll = Timer.periodic(const Duration(milliseconds: 120), (_) {
      unawaited(_refresh());
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final m = await kDesktopOngoingCallChannel.invokeMethod<Map<dynamic, dynamic>>(
        'snapshot',
      );
      if (!mounted) return;
      final map = m == null
          ? <String, dynamic>{'active': false}
          : Map<String, dynamic>.from(m);
      setState(() => _snap = map);
      final active = map['active'] == true;
      if (!active) {
        await _closeWindow();
      }
    } catch (e, st) {
      debugPrint('ongoing call snapshot: $e\n$st');
    }
  }

  Future<void> _closeWindow() async {
    if (_closeRequested) return;
    _closeRequested = true;
    _poll?.cancel();
    try {
      final self = await WindowController.fromCurrentEngine();
      await self.invokeMethod('window_close');
    } catch (e, st) {
      if (e is! WindowChannelException || e.code != 'CHANNEL_UNREGISTERED') {
        debugPrint('Ongoing call window close: $e\n$st');
      }
    }
  }

  Future<void> _rpc(String method) async {
    try {
      await kDesktopOngoingCallChannel.invokeMethod<void>(method);
    } catch (e, st) {
      debugPrint('ongoing call $method: $e\n$st');
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snap;
    final a = widget.args;
    final scheme = Theme.of(context).colorScheme;
    final videoSurface = a.preferVideoCallUi && !a.voiceOnly;

    final title = (snap?['title'] as String?) ?? a.title;
    final durationOrStatus =
        (snap?['durationOrStatus'] as String?) ?? '…';
    final micMuted = snap?['micMuted'] as bool? ?? false;
    final micLevel = (snap?['micCaptureLevel'] as num?)?.toDouble() ?? 0.0;
    final speakerOn = snap?['speakerOn'] as bool? ?? true;
    final cameraMuted = snap?['cameraMuted'] as bool? ?? true;
    final preferVideo = snap?['preferVideoCallUi'] as bool? ?? a.preferVideoCallUi;

    final small = Theme.of(context).textTheme.labelSmall;

    return Scaffold(
      backgroundColor: MatrixTheme.terminalBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'CALL',
                      style: small?.copyWith(
                        fontFamily: MatrixTheme.fontFamily,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        fontSize: 11,
                        color: MatrixTheme.matrixLightGreen,
                      ),
                    ),
                  ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    iconSize: 16,
                    tooltip: 'Open in Matrix',
                    onPressed: () => unawaited(_rpc('openFullCallInMain')),
                    icon: Icon(Icons.open_in_new, color: scheme.onSurface),
                  ),
                ],
              ),
              if (a.roomId.isNotEmpty)
                Text(
                  a.roomId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: small?.copyWith(
                    fontSize: 9,
                    color: scheme.onSurfaceVariant,
                    fontFamily: MatrixTheme.fontFamily,
                  ),
                ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(
                    preferVideo ? Icons.videocam : Icons.call,
                    size: 22,
                    color: MatrixTheme.matrixLightGreen.withValues(alpha: 0.9),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: MatrixTheme.fontFamily,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                durationOrStatus,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: MatrixTheme.fontFamily,
                  fontWeight: FontWeight.w600,
                  fontSize: 10,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: CallMicActivityWaveform(
                  level: micLevel,
                  muted: micMuted,
                  height: 28,
                  barWidth: 2.5,
                  gap: 1.5,
                  activeColor: MatrixTheme.matrixLightGreen.withValues(alpha: 0.9),
                ),
              ),
              if (videoSurface)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Video: open in Matrix',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: small?.copyWith(fontSize: 9),
                  ),
                ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: micMuted ? 'Unmute' : 'Mute',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 30,
                    ),
                    iconSize: 18,
                    icon: Icon(
                      micMuted ? Icons.mic_off : Icons.mic,
                      color: scheme.onSurface,
                    ),
                    onPressed: () => unawaited(_rpc('toggleMicrophone')),
                  ),
                  IconButton(
                    tooltip: speakerOn ? 'Speaker' : 'Earpiece',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 30,
                    ),
                    iconSize: 18,
                    icon: Icon(
                      speakerOn ? Icons.volume_up : Icons.phone_android,
                      color: scheme.onSurface,
                    ),
                    onPressed: () => unawaited(_rpc('toggleSpeaker')),
                  ),
                  if (preferVideo)
                    IconButton(
                      tooltip: cameraMuted ? 'Camera on' : 'Camera off',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 30,
                        minHeight: 30,
                      ),
                      iconSize: 18,
                      icon: Icon(
                        cameraMuted ? Icons.videocam_off : Icons.videocam,
                        color: scheme.onSurface,
                      ),
                      onPressed: () => unawaited(_rpc('toggleCamera')),
                    ),
                  IconButton(
                    tooltip: 'End call',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 30,
                    ),
                    iconSize: 20,
                    icon: Icon(Icons.call_end, color: scheme.error),
                    onPressed: () => unawaited(_rpc('hangUp')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
