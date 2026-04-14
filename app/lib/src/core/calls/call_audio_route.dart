import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

/// Routes call audio (ringback + WebRTC) between earpiece vs speaker on mobile.
abstract final class CallAudioRoute {
  static bool get _isIosAndroid =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  /// [speakerOn]: `false` → earpiece/receiver (typical phone ear); `true` → loudspeaker.
  static Future<void> applyForCall({required bool speakerOn}) async {
    if (!_isIosAndroid) return;

    final session = await AudioSession.instance;
    final bt = AVAudioSessionCategoryOptions.allowBluetooth |
        AVAudioSessionCategoryOptions.allowBluetoothA2dp;

    await session.configure(
      AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions: bt,
        avAudioSessionMode: AVAudioSessionMode.voiceChat,
        avAudioSessionRouteSharingPolicy:
            AVAudioSessionRouteSharingPolicy.defaultPolicy,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        // Do not pause VOIP capture when the system ducks other audio; that can mute uplink.
        androidWillPauseWhenDucked: false,
      ),
    );
    await session.setActive(true);

    if (Platform.isIOS) {
      await AVAudioSession().overrideOutputAudioPort(
        speakerOn
            ? AVAudioSessionPortOverride.speaker
            : AVAudioSessionPortOverride.none,
      );
    } else if (Platform.isAndroid) {
      await AndroidAudioManager().setSpeakerphoneOn(speakerOn);
    }
  }

  static Future<void> releaseAfterCall() async {
    if (!_isIosAndroid) return;
    try {
      if (Platform.isAndroid) {
        await AndroidAudioManager().setSpeakerphoneOn(false);
      }
      final session = await AudioSession.instance;
      await session.setActive(false);
    } catch (_) {}
  }
}
