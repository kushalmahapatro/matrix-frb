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
  }) async {
    // Keep PCM "dry" on mobile + macOS: Rust [NativeAudioSource] already disables WebRTC AEC/NS
    // on injected frames; stacking `record`'s voice processing often zeros uplink. Same idea as
    // the standalone LiveKit demo (minimal capture), plus explicit off on Apple/Google.
    final dryCapture = !kIsWeb &&
        (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);
    if (Platform.isIOS) {
      await _rec.ios?.manageAudioSession(false);
    }
    return _rec.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: numChannels,
        echoCancel: !dryCapture,
        noiseSuppress: !dryCapture,
        // `record` defaults to [AudioInterruptionMode.pause]: on Android it requests focus and
        // pauses capture on any transient loss. After LiveKit + [audio_session] configure, that
        // often fires once and never resumes (flat waveform, silent uplink). VoIP focus is owned
        // by [CallAudioRoute] / WebRTC instead.
        audioInterruption: AudioInterruptionMode.none,
        // Default Android source/mode is not tuned for VoIP; uplink can stay silent while
        // WebRTC holds communication focus. Match voiceCommunication + inCommunication.
        androidConfig: Platform.isAndroid
            ? AndroidRecordConfig(
                audioSource: AndroidAudioSource.voiceCommunication,
                audioManagerMode: AudioManagerMode.modeInCommunication,
              )
            : const AndroidRecordConfig(),
      ),
    );
  }

  @override
  Future<void> stopMicCapture() async {
    final r = _recorder;
    _recorder = null;
    if (r == null) return;
    try {
      await r.stop();
    } catch (_) {}
    try {
      await r.dispose();
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
