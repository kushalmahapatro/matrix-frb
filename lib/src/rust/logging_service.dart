import 'package:flutter/foundation.dart';

/// Logging service to handle Rust logs in Flutter
class RustLoggingService {
  static const String _tag = '[RUST]';

  /// Log a message from Rust
  static void logMessage(String level, String message) {
    final timestamp = DateTime.now().toIso8601String();
    final logMessage = '$_tag [$level] $timestamp: $message';

    switch (level.toLowerCase()) {
      case 'debug':
        if (kDebugMode) {
          debugPrint(logMessage);
        }
        break;
      case 'info':
        debugPrint(logMessage);
        break;
      case 'warn':
        debugPrint('⚠️  $logMessage');
        break;
      case 'error':
        debugPrint('❌ $logMessage');
        break;
      default:
        debugPrint(logMessage);
    }
  }

  /// Initialize Rust logging
  static Future<void> initializeLogging() async {
    try {
      // Set environment variable for Rust logging level
      // Note: This might not work on all platforms, but it's worth trying
      // The actual logging will be handled by the Rust side
      debugPrint('$_tag Initializing Rust logging...');
    } catch (e) {
      debugPrint('$_tag Failed to initialize logging: $e');
    }
  }
}
