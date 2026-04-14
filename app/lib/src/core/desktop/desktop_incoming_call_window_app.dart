import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:matrix/src/core/desktop/desktop_auxiliary_window_channel.dart';
import 'package:matrix/src/core/desktop/desktop_compact_call_window_position.dart';
import 'package:matrix/src/core/desktop/desktop_compact_call_window_size.dart';
import 'package:matrix/src/core/desktop/desktop_incoming_call_main_bridge.dart';
import 'package:matrix/src/core/desktop/desktop_ui_helpers.dart';
import 'package:matrix/src/core/desktop/desktop_window_args.dart';
import 'package:matrix/src/theme/matrix_theme.dart';
import 'package:window_manager/window_manager.dart';

/// Lightweight second engine: incoming ring UI only. Accept / decline RPC to main.
Future<void> runDesktopIncomingCallWindowApp(
  DesktopIncomingCallWindowArgs args,
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
          title: 'Incoming call',
        ),
        () async {
          await positionDesktopCompactCallWindowBottomRight();
          await windowManager.show();
          await windowManager.focus();
        },
      );
    } catch (e, st) {
      debugPrint('runDesktopIncomingCallWindowApp window_manager: $e\n$st');
    }
  }

  runApp(_IncomingCallWindowRoot(args: args));
}

class _IncomingCallWindowRoot extends StatelessWidget {
  const _IncomingCallWindowRoot({required this.args});

  final DesktopIncomingCallWindowArgs args;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: MatrixTheme.getTheme(args.isDarkMode, useDesktopChrome: true),
      home: _IncomingCallScaffold(args: args),
    );
  }
}

class _IncomingCallScaffold extends StatefulWidget {
  const _IncomingCallScaffold({required this.args});

  final DesktopIncomingCallWindowArgs args;

  @override
  State<_IncomingCallScaffold> createState() => _IncomingCallScaffoldState();
}

class _IncomingCallScaffoldState extends State<_IncomingCallScaffold> {
  Timer? _timer;
  var _secondsLeft = 30;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _secondsLeft -= 1);
      if (_secondsLeft <= 0) {
        _timer?.cancel();
        unawaited(_decline('Missed call'));
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _closeWindow() async {
    try {
      final self = await WindowController.fromCurrentEngine();
      await self.invokeMethod('window_close');
    } catch (e, st) {
      debugPrint('Incoming call window close: $e\n$st');
    }
  }

  Future<void> _accept() async {
    _timer?.cancel();
    final a = widget.args;
    try {
      await kDesktopIncomingCallChannel
          .invokeMethod<void>('incomingCallAccepted', <String, dynamic>{
            'roomId': a.roomId,
            'roomName': a.roomName,
            if (a.callKitId != null && a.callKitId!.isNotEmpty)
              'callKitId': a.callKitId,
          });
    } catch (e, st) {
      debugPrint('incomingCallAccepted RPC: $e\n$st');
    }
    if (mounted) await _closeWindow();
  }

  Future<void> _decline(String reason) async {
    _timer?.cancel();
    final a = widget.args;
    try {
      await kDesktopIncomingCallChannel
          .invokeMethod<void>('incomingCallDeclined', <String, dynamic>{
            'roomId': a.roomId,
            'rtcEventId': a.rtcEventId,
            'roomName': a.roomName,
            if (a.callKitId != null && a.callKitId!.isNotEmpty)
              'callKitId': a.callKitId,
            'reason': reason,
          });
    } catch (e, st) {
      debugPrint('incomingCallDeclined RPC: $e\n$st');
    }
    if (mounted) await _closeWindow();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final a = widget.args;

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
                      'RING',
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
                    tooltip: 'Dismiss',
                    onPressed: () => unawaited(_decline('Dismissed')),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Text(
                a.callerLabel,
                style: TextStyle(
                  fontFamily: MatrixTheme.fontFamily,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: MatrixTheme.matrixLightGreen,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                a.roomName,
                style: small?.copyWith(
                  fontSize: 10,
                  color: scheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Text(
                '$_secondsLeft s',
                textAlign: TextAlign.center,
                style: small?.copyWith(
                  fontSize: 10,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    tooltip: 'Decline',
                    icon: Icon(Icons.call_end, color: scheme.error, size: 26),
                    onPressed: () => unawaited(_decline('Declined')),
                  ),
                  IconButton(
                    tooltip: 'Accept',
                    icon: Icon(
                      Icons.call,
                      size: 26,
                      color: MatrixTheme.matrixLightGreen,
                    ),
                    onPressed: () => unawaited(_accept()),
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
