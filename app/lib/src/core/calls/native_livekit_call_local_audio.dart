import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';

/// Mic capture + ringback used by [NativeLiveKitCallSession].
///
/// Production uses [LiveNativeLiveKitCallLocalAudio]; tests use [NoopNativeLiveKitCallLocalAudio]
/// to avoid `record` / `just_audio` platform channels.
abstract interface class NativeLiveKitCallLocalAudio {
  Future<void> prepareMicPrerequisites();

  Future<Stream<Uint8List>> openMicPcmStream({
    required int sampleRate,
    required int numChannels,
  });

  Future<void> stopMicCapture();

  Future<void> setRingVolume(double volume);

  Future<void> startRingbackLoopingFile(String path);

  Future<void> stopRingback();

  Future<void> dispose();
}

NativeLiveKitCallLocalAudio createNativeLiveKitCallLocalAudio({
  required bool noop,
}) =>
    noop ? const NoopNativeLiveKitCallLocalAudio() : LiveNativeLiveKitCallLocalAudio();

final class LiveNativeLiveKitCallLocalAudio implements NativeLiveKitCallLocalAudio {
  AudioRecorder? _recorder;
  AudioPlayer? _player;

  AudioRecorder get _rec => _recorder ??= AudioRecorder();

  AudioPlayer get _ring => _player ??= AudioPlayer();

  @override
  Future<void> prepareMicPrerequisites() async {
    final micOk = await _rec.hasPermission();
    if (!micOk) {
      throw Exception('Microphone permission denied.');
    }
    if (!await _rec.isEncoderSupported(AudioEncoder.pcm16bits)) {
      throw Exception('PCM16 capture is not supported on this device.');
    }
  }

  @override
  Future<Stream<Uint8List>> openMicPcmStream({
    required int sampleRate,
    required int numChannels,
  }) {
    // On mobile, PCM is pushed into a custom WebRTC [NativeAudioSource] with AEC/AGC/NS already
    // disabled in Rust. `record`'s built-in AEC/NS — especially with speakerphone — often drives
    // uplink toward silence; keep capture "dry" here and let the stack handle echo if needed.
    final useBuiltInNsAec = kIsWeb ||
        (!Platform.isAndroid && !Platform.isIOS);
    return _rec.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: numChannels,
        echoCancel: useBuiltInNsAec,
        noiseSuppress: useBuiltInNsAec,
        streamBufferSize: 1920,
      ),
    );
  }

  @override
  Future<void> stopMicCapture() async {
    try {
      await _recorder?.stop();
    } catch (_) {}
  }

  @override
  Future<void> setRingVolume(double volume) => _ring.setVolume(volume);

  @override
  Future<void> startRingbackLoopingFile(String path) async {
    await _ring.setLoopMode(LoopMode.one);
    await _ring.setFilePath(path);
    await _ring.setVolume(0.35);
    await _ring.play();
  }

  @override
  Future<void> stopRingback() async {
    final p = _player;
    if (p == null) return;
    try {
      await p.stop();
    } catch (_) {}
    try {
      await p.seek(Duration.zero);
    } catch (_) {}
    try {
      await p.setVolume(0);
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    try {
      await _recorder?.dispose();
    } catch (_) {}
    try {
      await _player?.dispose();
    } catch (_) {}
  }
}

final class NoopNativeLiveKitCallLocalAudio implements NativeLiveKitCallLocalAudio {
  const NoopNativeLiveKitCallLocalAudio();

  @override
  Future<void> prepareMicPrerequisites() async {}

  @override
  Future<Stream<Uint8List>> openMicPcmStream({
    required int sampleRate,
    required int numChannels,
  }) async =>
      const Stream<Uint8List>.empty();

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
