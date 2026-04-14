import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/src/core/calls/call_history_store.dart';
import 'package:matrix/src/core/calls/livekit_native_bridge.dart';
import 'package:matrix/src/core/calls/native_livekit_call_session.dart';
import 'package:matrix_sdk/matrix_sdk.dart';
import 'package:mocktail/mocktail.dart';

class MockMatrixClient extends Mock implements MatrixClient {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('second session can connect after first hangUp (shared fake bridge)', () async {
    final mock = MockMatrixClient();
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
    await first.setSpeakerOn(true);
    await first.setSpeakerOn(false);

    await first.hangUp();
    expect(fake.closeCount, 1);

    final second = NativeLiveKitCallSession(args());
    await second.ensureStarted();
    expect(second.phase, NativeLiveKitCallPhase.connected);
    expect(fake.connectCount, 2);

    await second.hangUp();
    expect(fake.closeCount, 2);
  });
}

