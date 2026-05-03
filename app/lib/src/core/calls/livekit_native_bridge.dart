import 'dart:typed_data';

import 'package:matrix_sdk/matrix_sdk.dart';

/// Abstraction over FRB LiveKit APIs for production use and testing.
abstract class LiveKitNativeBridge {
  Future<void> connect({
    required String url,
    required String token,
    required bool voiceOnly,
  });

  Future<void> close();

  Future<String> connectionState();

  Future<int> remoteParticipantCount();

  Future<void> setMicrophoneMuted({required bool muted});

  Future<void> setCameraMuted({required bool muted});

  Future<void> publishLocalCameraTrack();

  Future<void> pushAudioPcm16({
    required List<int> pcm,
    required int sampleRate,
    required int numChannels,
  });

  Future<void> pushVideoI420({
    required int width,
    required int height,
    required List<int> data,
    required int timestampUs,
    required int rotationDegrees,
  });

  /// Mono PCM16 @ 48 kHz from the first remote mic (Rust ring buffer); empty if none pending.
  Future<Int16List> pullRemoteAudioPcm16({required int maxSamples});

  /// Latest remote camera frame (tight I420) since the last pull; [LivekitRemoteVideoI420.width] is
  /// zero when none is pending.
  Future<LivekitRemoteVideoI420> tryPullRemoteVideoI420();
}

/// Default: delegates to generated [matrix_sdk] bindings.
class DefaultLiveKitNativeBridge implements LiveKitNativeBridge {
  DefaultLiveKitNativeBridge._();
  static final DefaultLiveKitNativeBridge instance = DefaultLiveKitNativeBridge._();

  @override
  Future<void> connect({
    required String url,
    required String token,
    required bool voiceOnly,
  }) =>
      livekitSessionConnect(url: url, token: token, voiceOnly: voiceOnly);

  @override
  Future<void> close() => livekitSessionClose();

  @override
  Future<String> connectionState() => livekitSessionConnectionState();

  @override
  Future<int> remoteParticipantCount() => livekitSessionRemoteParticipantCount();

  @override
  Future<void> setMicrophoneMuted({required bool muted}) =>
      livekitSessionSetMicrophoneMuted(muted: muted);

  @override
  Future<void> setCameraMuted({required bool muted}) =>
      livekitSessionSetCameraMuted(muted: muted);

  @override
  Future<void> publishLocalCameraTrack() =>
      livekitSessionPublishLocalCameraTrack();

  @override
  Future<void> pushAudioPcm16({
    required List<int> pcm,
    required int sampleRate,
    required int numChannels,
  }) =>
      livekitSessionPushAudioPcm16(
        pcm: pcm,
        sampleRate: sampleRate,
        numChannels: numChannels,
      );

  @override
  Future<void> pushVideoI420({
    required int width,
    required int height,
    required List<int> data,
    required int timestampUs,
    required int rotationDegrees,
  }) =>
      livekitSessionPushVideoI420(
        width: width,
        height: height,
        data: data,
        timestampUs: timestampUs,
        rotationDegrees: rotationDegrees,
      );

  @override
  Future<Int16List> pullRemoteAudioPcm16({required int maxSamples}) =>
      livekitSessionPullRemoteAudioPcm16(maxSamples: BigInt.from(maxSamples));

  @override
  Future<LivekitRemoteVideoI420> tryPullRemoteVideoI420() =>
      livekitSessionTryPullRemoteVideoI420();
}

/// In-memory fake for widget/integration tests (no Rust).
class FakeLiveKitNativeBridge implements LiveKitNativeBridge {
  FakeLiveKitNativeBridge();

  bool connected = false;
  bool closed = true;
  int connectCount = 0;
  int closeCount = 0;
  int pushAudioCount = 0;
  int lastPushAudioSampleCount = 0;
  int pushVideoCount = 0;
  bool micMuted = false;
  bool camMuted = false;
  int publishCameraCount = 0;

  @override
  Future<void> connect({
    required String url,
    required String token,
    required bool voiceOnly,
  }) async {
    connectCount++;
    connected = true;
    closed = false;
  }

  @override
  Future<void> close() async {
    closeCount++;
    connected = false;
    closed = true;
  }

  @override
  Future<String> connectionState() async =>
      connected ? 'Connected' : 'idle';

  @override
  Future<int> remoteParticipantCount() async => 0;

  @override
  Future<void> setMicrophoneMuted({required bool muted}) async {
    micMuted = muted;
  }

  @override
  Future<void> setCameraMuted({required bool muted}) async {
    camMuted = muted;
  }

  @override
  Future<void> publishLocalCameraTrack() async {
    publishCameraCount++;
  }

  @override
  Future<void> pushAudioPcm16({
    required List<int> pcm,
    required int sampleRate,
    required int numChannels,
  }) async {
    pushAudioCount++;
    lastPushAudioSampleCount = pcm.length;
  }

  @override
  Future<void> pushVideoI420({
    required int width,
    required int height,
    required List<int> data,
    required int timestampUs,
    required int rotationDegrees,
  }) async {
    pushVideoCount++;
  }

  @override
  Future<Int16List> pullRemoteAudioPcm16({required int maxSamples}) async =>
      Int16List(0);

  @override
  Future<LivekitRemoteVideoI420> tryPullRemoteVideoI420() async =>
      LivekitRemoteVideoI420(width: 0, height: 0, data: Uint8List(0));
}
