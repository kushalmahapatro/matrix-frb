import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// iOS: requests mic via [AVAudioSession.requestRecordPermission] from the Runner host.
///
/// Complements [permission_handler], which uses `AVCaptureDevice` for audio. Using the
/// audio-session path matches voice recording / calls and reliably surfaces
/// `NSMicrophoneUsageDescription` and **Settings → Privacy & Security → Microphone**.
const _channel = MethodChannel('dev.inve.matrixchat/microphone');

bool get _isIosDevice =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

Future<bool?> iosRequestRecordPermission() async {
  if (!_isIosDevice) return null;
  try {
    final granted = await _channel.invokeMethod<bool>('requestAccess');
    return granted;
  } on PlatformException {
    return null;
  }
}

/// `undetermined` | `denied` | `granted`, or null if unavailable.
Future<String?> iosRecordPermissionStatus() async {
  if (!_isIosDevice) return null;
  try {
    final s = await _channel.invokeMethod<String>('recordPermissionStatus');
    return s;
  } on PlatformException {
    return null;
  }
}
