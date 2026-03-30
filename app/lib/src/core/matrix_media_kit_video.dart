import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// iOS Simulator often crashes or glitches with GPU-backed video output (Metal);
/// CPU decoding is slower but stable enough for previews.
bool matrixPlaybackIsIosSimulator() {
  if (kIsWeb) return false;
  try {
    return Platform.isIOS &&
        Platform.environment.containsKey('SIMULATOR_DEVICE_NAME');
  } on Object {
    return false;
  }
}

VideoControllerConfiguration matrixPlaybackVideoControllerConfiguration() {
  return matrixPlaybackIsIosSimulator()
      ? const VideoControllerConfiguration(enableHardwareAcceleration: false)
      : const VideoControllerConfiguration();
}

/// [VideoController] schedules native setup on a post-frame callback; opening
/// the [Player] before that completes can crash native code (resize / texture).
Future<void> matrixAwaitVideoControllerPlatformReady(
  VideoController controller,
) =>
    controller.platform.future;

/// Sniff ISO BMFF (mp4/mov/…), WebM/Matroska, or AVI — avoids feeding JSON/HTML
/// or other non-media bytes to libmpv (can abort the process on some platforms).
bool matrixBytesLookLikeVideoContainer(Uint8List bytes) {
  if (bytes.length < 12) return false;
  if (bytes[4] == 0x66 &&
      bytes[5] == 0x74 &&
      bytes[6] == 0x79 &&
      bytes[7] == 0x70) {
    return true;
  }
  if (bytes[0] == 0x1a &&
      bytes[1] == 0x45 &&
      bytes[2] == 0xdf &&
      bytes[3] == 0xa3) {
    return true;
  }
  if (bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x41 &&
      bytes[9] == 0x56 &&
      bytes[10] == 0x49) {
    return true;
  }
  return false;
}
