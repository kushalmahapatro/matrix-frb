import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/src/core/calls/call_history_store.dart';
import 'package:matrix/src/core/calls/livekit_native_bridge.dart';
import 'package:matrix/src/core/calls/native_livekit_call_host.dart';
import 'package:matrix/src/core/calls/native_livekit_call_session.dart';
import 'package:matrix_sdk/matrix_sdk.dart' show MatrixClient;
import 'package:mocktail/mocktail.dart';

class _MockMatrixClient extends Mock implements MatrixClient {}

/// Regression: desktop must call [NativeLiveKitCallSession.ensureStarted] because
/// [NativeLiveKitCallScreen] is not mounted, otherwise phase stays idle and no popout.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final host = NativeLiveKitCallHost.instance;

  setUp(() {
    host.debugResetForTest();
  });

  tearDown(() {
    host.debugResetForTest();
    debugDefaultTargetPlatformOverride = null;
  });

  NativeLiveKitCallSession makeSession() {
    final mock = _MockMatrixClient();
    return NativeLiveKitCallSession(
      NativeLiveKitCallArgs(
        matrixClient: mock,
        livekitUrl: 'https://example.invalid',
        accessToken: 'tok',
        title: 'Room',
        matrixRoomId: '!abc:example.org',
        voiceOnly: true,
        historyDirection: CallHistoryDirection.outgoing,
        joinedExisting: true,
        liveKitBridge: FakeLiveKitNativeBridge(),
        debugSkipPlatformAudioDevices: true,
        debugSkipCallHistoryForTest: true,
      ),
    );
  }

  group('desktop target (simulated)', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    });

    test(
      'beginCallDesktopDetached + ensureStarted yields connecting then popout visibility',
      () async {
        final session = makeSession();
        expect(session.phase, NativeLiveKitCallPhase.idle);
        expect(host.showDesktopOngoingCallPopout, isFalse);

        host.beginCallDesktopDetached(session);
        expect(host.routeVisible, isFalse);
        expect(host.session, same(session));
        // Idle until ensureStarted runs.
        expect(host.showDesktopOngoingCallPopout, isFalse);

        await session.ensureStarted();
        expect(session.phase, NativeLiveKitCallPhase.connected);
        expect(host.showDesktopOngoingCallPopout, isTrue);
        expect(host.showInAppOngoingCallStrip, isTrue);
      },
    );

    test('full-screen route visible hides desktop popout flag', () async {
      final session = makeSession();
      host.beginCallDesktopDetached(session);
      await session.ensureStarted();
      expect(host.showDesktopOngoingCallPopout, isTrue);

      host.markRouteVisible(true);
      expect(host.showDesktopOngoingCallPopout, isFalse);
      expect(host.showInAppOngoingCallStrip, isTrue);
    });
  });

  group('mobile target (simulated)', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    });

    test('showInAppOngoingCallStrip only when minimized + connected', () async {
      final session = makeSession();
      host.beginCall(session);
      await session.ensureStarted();
      expect(session.phase, NativeLiveKitCallPhase.connected);
      // Route “visible”: no minimized strip on mobile.
      expect(host.showInAppOngoingCallStrip, isFalse);

      host.markRouteVisible(false);
      expect(host.showInAppOngoingCallStrip, isTrue);
    });
  });
}
