import 'package:flutter/foundation.dart';
import 'package:matrix/src/rust/api/logger.dart';
import 'package:logger/logger.dart';

/// Logging service to handle Rust logs in Flutter
class LoggingService {
  static const String _tag = '[RUST]';

  /// Log a message from Rust
  static void _logMessage(LogEntry logEntry) {
    final level = logEntry.level;
    final message = logEntry.message;
    final timestamp = logEntry.timestamp;
    final logMessage = '${logEntry.tag} $timestamp: $message';

    switch (level.toLowerCase()) {
      case 'debug':
        if (kDebugMode) {
          _logger.d(logMessage);
        }
        break;
      case 'info':
        _logger.i(logMessage);
        break;
      case 'warn':
        _logger.w(logMessage);
        break;
      case 'error':
        _logger.e(logMessage);
        break;
      default:
        _logger.i(logMessage);
    }
  }

  static late Logger _logger;

  /// Initialize Rust logging
  static Future<void> initializeLogging() async {
    _logger = Logger(printer: PrettyPrinter());

    final Stream<LogEntry> loggerStream = initLogger();
    loggerStream.listen((logEntry) {
      _logMessage(
        LogEntry(
          level: logEntry.level,
          message: logEntry.message,
          timestamp: logEntry.timestamp,
          tag: '$_tag ${logEntry.tag}',
        ),
      );
    });
  }

  static void info(String tag, String message) {
    _logMessage(
      LogEntry(
        level: "info",
        message: message,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        tag: tag,
      ),
    );
  }

  static void debug(String tag, String message) {
    _logMessage(
      LogEntry(
        level: "debug",
        message: message,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        tag: tag,
      ),
    );
  }

  static void warn(String tag, String message) {
    _logMessage(
      LogEntry(
        level: "warn",
        message: message,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        tag: tag,
      ),
    );
  }

  static void error(String tag, String message) {
    _logMessage(
      LogEntry(
        level: "error",
        message: message,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        tag: tag,
      ),
    );
  }
}
