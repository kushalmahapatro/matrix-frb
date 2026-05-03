import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/src/core/calls/livekit_native_bridge.dart';
import 'package:matrix/src/core/calls/native_livekit_call_host.dart';
import 'package:matrix/src/core/calls/native_livekit_call_session.dart';
import 'package:matrix_sdk/matrix_sdk.dart';
import 'package:mocktail/mocktail.dart';

class MockMatrixClient extends Mock implements MatrixClient {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final host = NativeLiveKitCallHost.instance;

  setUp(() {
    host.debugResetForTest();
  });

  tearDown(() {
    host.debugResetForTest();
  });

  test('prepareForNewCall hangUp clears host and closes fake bridge', () async {
    final mock = MockMatrixClient();
    final fake = FakeLiveKitNativeBridge();
    final session = NativeLiveKitCallSession(
      NativeLiveKitCallArgs(
        matrixClient: mock,
        livekitUrl: 'https://example.invalid',
        accessToken: 'tok',
        title: 'Room',
        matrixRoomId: '!abc:example.org',
        liveKitBridge: fake,
        debugSkipPlatformAudioDevices: true,
      ),
    );
    host.debugBindSessionForTest(session);
    await host.prepareForNewCall();
    expect(host.session, isNull);
    expect(fake.closeCount, greaterThanOrEqualTo(1));
  });
}
