import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/src/core/calls/livekit_native_bridge.dart';

void main() {
  test('FakeLiveKitNativeBridge connect/close twice', () async {
    final b = FakeLiveKitNativeBridge();
    await b.connect(url: 'u', token: 't', voiceOnly: true);
    expect(b.connectCount, 1);
    expect(b.connected, isTrue);
    await b.close();
    expect(b.closeCount, 1);
    expect(b.connected, isFalse);
    await b.connect(url: 'u', token: 't', voiceOnly: true);
    expect(b.connectCount, 2);
    await b.close();
    expect(b.closeCount, 2);
  });

  test('FakeLiveKitNativeBridge mute and push counters', () async {
    final b = FakeLiveKitNativeBridge();
    await b.connect(url: 'u', token: 't', voiceOnly: true);
    await b.setMicrophoneMuted(muted: true);
    expect(b.micMuted, isTrue);
    await b.pushAudioPcm16(pcm: [0, 0], sampleRate: 48000, numChannels: 1);
    expect(b.pushAudioCount, 1);
    expect(b.lastPushAudioSampleCount, 2);
    await b.pushVideoI420(
      width: 2,
      height: 2,
      data: [1],
      timestampUs: 0,
      rotationDegrees: 0,
    );
    expect(b.pushVideoCount, 1);
  });
}
