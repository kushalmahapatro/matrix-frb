import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:matrix/src/core/calls/call_history_store.dart';
import 'package:matrix/src/core/calls/native_livekit_call_host.dart';
import 'package:matrix/src/core/calls/native_livekit_call_local_audio.dart';
import 'package:matrix/src/core/calls/native_livekit_call_session.dart';
import 'package:matrix/src/core/calls/livekit_native_bridge.dart';
import 'package:matrix_sdk/matrix_sdk.dart';
import 'package:mocktail/mocktail.dart';

class _MockMatrixClient extends Mock implements MatrixClient {}

/// One-shot 48 kHz mono PCM16 chunk (480 samples) — matches [NativeLiveKitCallSession] push size.
final class _SyntheticPcmLocalAudio implements NativeLiveKitCallLocalAudio {
  const _SyntheticPcmLocalAudio();

  @override
  Future<void> prepareMicPrerequisites() async {}

  @override
  Future<Stream<Uint8List>> openMicPcmStream({
    required int sampleRate,
    required int numChannels,
  }) async {
    final bd = ByteData(960);
    for (var i = 0; i < 480; i++) {
      bd.setInt16(i * 2, (i * 100) % 3000, Endian.little);
    }
    return Stream<Uint8List>.value(bd.buffer.asUint8List());
  }

  @override
  Future<void> stopMicCapture() async {}

  @override
  Future<void> setRingVolume(double volume) async {}

  @override
  Future<void> startRingbackLoopingFile(String path) async {}

  @override
  Future<void> stopRingback() async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('NativeLiveKitCallSession: fake bridge, two connects', (tester) async {
    final mock = _MockMatrixClient();
    final fake = FakeLiveKitNativeBridge();

    NativeLiveKitCallArgs args() => NativeLiveKitCallArgs(
      matrixClient: mock,
      livekitUrl: 'https://example.invalid',
      accessToken: 'tok',
      title: 'Room',
      matrixRoomId: '!abc:example.org',
      voiceOnly: true,
      historyDirection: CallHistoryDirection.incoming,
      liveKitBridge: fake,
      debugSkipPlatformAudioDevices: true,
      debugSkipCallHistoryForTest: true,
    );

    final first = NativeLiveKitCallSession(args());
    await first.ensureStarted();
    expect(first.phase, NativeLiveKitCallPhase.connected);
    expect(fake.connectCount, 1);
    await first.setMicrophoneMuted(true);
    expect(fake.micMuted, isTrue);
    await first.hangUp();
    expect(fake.closeCount, 1);

    final second = NativeLiveKitCallSession(args());
    await second.ensureStarted();
    expect(second.phase, NativeLiveKitCallPhase.connected);
    expect(fake.connectCount, 2);
    await second.hangUp();
    expect(fake.closeCount, 2);
  });

  testWidgets('Desktop detached: host flags after beginCallDesktopDetached + ensureStarted', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final host = NativeLiveKitCallHost.instance;
      host.debugResetForTest();

      final mock = _MockMatrixClient();
      final fake = FakeLiveKitNativeBridge();
      final session = NativeLiveKitCallSession(
        NativeLiveKitCallArgs(
          matrixClient: mock,
          livekitUrl: 'https://example.invalid',
          accessToken: 'tok',
          title: 'Room',
          matrixRoomId: '!abc:example.org',
          voiceOnly: true,
          historyDirection: CallHistoryDirection.outgoing,
          joinedExisting: true,
          liveKitBridge: fake,
          debugSkipPlatformAudioDevices: true,
          debugSkipCallHistoryForTest: true,
        ),
      );

      host.beginCallDesktopDetached(session);
      expect(host.routeVisible, isFalse);
      expect(host.showDesktopOngoingCallPopout, isFalse);

      await session.ensureStarted();
      expect(session.phase, NativeLiveKitCallPhase.connected);
      expect(host.showDesktopOngoingCallPopout, isTrue);
      expect(host.showInAppOngoingCallStrip, isTrue);

      await session.hangUp();
      host.debugResetForTest();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'NativeLiveKitCallSession: synthetic PCM reaches fake bridge after connect',
    (tester) async {
      final mock = _MockMatrixClient();
      final fake = FakeLiveKitNativeBridge();
      final session = NativeLiveKitCallSession(
        NativeLiveKitCallArgs(
          matrixClient: mock,
          livekitUrl: 'https://example.invalid',
          accessToken: 'tok',
          title: 'Room',
          matrixRoomId: '!abc:example.org',
          voiceOnly: true,
          historyDirection: CallHistoryDirection.incoming,
          liveKitBridge: fake,
          debugSkipCallHistoryForTest: true,
          localAudioForTest: const _SyntheticPcmLocalAudio(),
        ),
      );
      await session.ensureStarted();
      expect(fake.connectCount, 1);
      expect(session.phase, NativeLiveKitCallPhase.connected);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(fake.pushAudioCount, greaterThan(0));
      expect(fake.lastPushAudioSampleCount, 480);
      await session.hangUp();
    },
  );
}
