import 'package:flutter/foundation.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

/// Custom logging handler for Flutter Rust Bridge
class CustomLoggingHandler extends BaseHandler {
  void log(String message) {
    // Forward Rust logs to Flutter console
    debugPrint('[RUST_BRIDGE] $message');
  }
}
