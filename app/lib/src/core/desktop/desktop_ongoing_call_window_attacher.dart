import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:matrix/src/core/calls/native_livekit_call_host.dart';
import 'package:matrix/src/core/calls/native_livekit_call_session.dart';
import 'package:matrix/src/core/desktop/desktop_ongoing_call_window_opener.dart';
import 'package:matrix/src/core/desktop/desktop_ui_helpers.dart';

/// Opens the ongoing-call popout when [NativeLiveKitCallHost.showDesktopOngoingCallPopout] is true.
class DesktopOngoingCallWindowAttacher extends StatefulWidget {
  const DesktopOngoingCallWindowAttacher({
    super.key,
    required this.child,
    required this.isDarkMode,
  });

  final Widget child;
  final bool isDarkMode;

  @override
  State<DesktopOngoingCallWindowAttacher> createState() =>
      _DesktopOngoingCallWindowAttacherState();
}

class _DesktopOngoingCallWindowAttacherState
    extends State<DesktopOngoingCallWindowAttacher> {
  NativeLiveKitCallSession? _wiredSession;
  bool _syncPostFrameScheduled = false;

  @override
  void initState() {
    super.initState();
    NativeLiveKitCallHost.instance.addListener(_onHostOrSession);
    _rewireSessionListener();
    _scheduleSync();
  }

  @override
  void dispose() {
    NativeLiveKitCallHost.instance.removeListener(_onHostOrSession);
    _wiredSession?.removeListener(_onHostOrSession);
    super.dispose();
  }

  void _rewireSessionListener() {
    final s = NativeLiveKitCallHost.instance.session;
    if (_wiredSession == s) return;
    _wiredSession?.removeListener(_onHostOrSession);
    _wiredSession = s;
    _wiredSession?.addListener(_onHostOrSession);
  }

  void _onHostOrSession() {
    _rewireSessionListener();
    _scheduleSync();
  }

  void _scheduleSync() {
    if (_syncPostFrameScheduled) return;
    _syncPostFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncPostFrameScheduled = false;
      if (!mounted) return;
      unawaited(_sync());
    });
  }

  Future<void> _sync() async {
    if (!mounted) return;
    if (kIsWeb || !isDesktopTargetPlatform()) return;
    final host = NativeLiveKitCallHost.instance;
    final want = host.showDesktopOngoingCallPopout;
    if (want) {
      final session = host.session;
      if (session == null) return;
      await DesktopOngoingCallWindowOpener.ensureOpen(
        session,
        isDarkMode: widget.isDarkMode,
      );
    } else {
      await DesktopOngoingCallWindowOpener.closeActive();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
