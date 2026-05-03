import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

/// Routes call audio (ringback + WebRTC) between earpiece vs speaker on mobile,
/// and activates a VoIP-friendly session on **macOS** (desktop LiveKit playout + `record`).
abstract final class CallAudioRoute {
  /// iOS/Android full session; macOS uses the same Darwin category via `audio_session` plugin.
  static bool get _shouldConfigureSession =>
      !kIsWeb &&
      (Platform.isIOS || Platform.isAndroid || Platform.isMacOS);

  /// [speakerOn]: `false` → earpiece / wired / Bluetooth (system routing); `true` → loudspeaker.
  ///
  /// Always re-runs [AudioSession.configure] + [setActive] before changing the output route.
  /// Skipping configure on toggles was observed to leave speaker / earpiece switches ineffective
  /// after WebRTC + `record` have taken audio focus.
  static Future<void> applyForCall({required bool speakerOn}) async {
    if (!_shouldConfigureSession) return;

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
      if (speakerOn) {
        try {
          await AndroidAudioManager().clearCommunicationDevice();
        } catch (_) {}
      }
      await AndroidAudioManager().setSpeakerphoneOn(speakerOn);
    }
    // macOS: category/mode is set via `configure` + `setActive`; default output device is used.
  }

  static Future<void> releaseAfterCall() async {
    if (!_shouldConfigureSession) return;
    try {
      if (Platform.isAndroid) {
        try {
          await AndroidAudioManager().clearCommunicationDevice();
        } catch (_) {}
        await AndroidAudioManager().setSpeakerphoneOn(false);
      }
      final session = await AudioSession.instance;
      await session.setActive(false);
    } catch (_) {}
  }

  /// Clears an explicit communication output (Android 12+). No-op on other platforms.
  static Future<void> androidClearCommunicationDevice() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await AndroidAudioManager().clearCommunicationDevice();
    } catch (_) {}
  }

  /// Routes call audio to a specific communication device when supported (Android 12+).
  /// Returns `false` if the device was not found or the API is unavailable.
  static Future<bool> androidTrySetCommunicationDevice(String deviceIdStr) async {
    if (kIsWeb || !Platform.isAndroid) return false;
    final id = int.tryParse(deviceIdStr);
    if (id == null) return false;
    try {
      final mgr = AndroidAudioManager();
      final list = await mgr.getAvailableCommunicationDevices();
      final match = list.where((d) => d.id == id).toList();
      if (match.isEmpty) return false;
      return await mgr.setCommunicationDevice(match.first);
    } catch (_) {
      return false;
    }
  }
}
