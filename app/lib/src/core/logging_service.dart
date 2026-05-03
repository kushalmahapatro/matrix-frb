import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:matrix_sdk/matrix_sdk.dart';

/// Parses [stackTrace] and returns file, line, and function name (target).
/// If [skipFilePathContains] is set, skips frames from that path and returns
/// the first frame from another file (caller site).
({String file, int line, String target}) _parseCallerFrame(
  StackTrace stackTrace, {
  String? skipFilePathContains,
  String defaultFile = 'unknown',
  int defaultLine = 0,
  String defaultTarget = 'unknown',
}) {
  final lines = stackTrace.toString().trim().split('\n');
  // Match VM format: "#0   _logMessage (package:app/.../file.dart:123:45)"
  final fileRegex = RegExp(r'\(([^)]+\.dart):(\d+)');
  final targetRegex = RegExp(r'\s+(\w+)\s+\(');

  for (final line in lines) {
    final fileMatch = fileRegex.firstMatch(line);
    if (fileMatch == null) continue;
    final file = fileMatch.group(1)!;
    if (skipFilePathContains != null && file.contains(skipFilePathContains)) {
      continue;
    }
    final lineNum = int.tryParse(fileMatch.group(2) ?? '') ?? defaultLine;
    final targetMatch = targetRegex.firstMatch(line);
    final target = targetMatch?.group(1) ?? defaultTarget;
    return (file: file, line: lineNum, target: target);
  }
  return (file: defaultFile, line: defaultLine, target: defaultTarget);
}

/// Logging service to handle Rust logs in Flutter
class LoggingService {
  static void _logMessage(LogEntry logEntry, [StackTrace? stackTrace]) {
    final level = logEntry.level;
    final message = logEntry.message;
    final timestamp = logEntry.timestamp;
    final logMessage = '${logEntry.tag} $timestamp: $message';

    final stack = stackTrace ?? StackTrace.current;
    final loc = _parseCallerFrame(
      stack,
      skipFilePathContains: stackTrace != null ? 'logging_service' : null,
    );
    // Prefer Rust tag as target (module path); fall back to Dart function name.
    final target = logEntry.tag.isNotEmpty ? logEntry.tag : loc.target;

    switch (level.toLowerCase()) {
      case 'debug':
        if (kDebugMode) {
          logEvent(
            file: loc.file,
            line: loc.line,
            level: LogLevel.debug,
            target: target,
            message: message,
          );
        }
        break;
      case 'info':
        logEvent(
          file: loc.file,
          line: loc.line,
          level: LogLevel.info,
          target: target,
          message: message,
        );
        break;
      case 'warn':
        logEvent(
          file: loc.file,
          line: loc.line,
          level: LogLevel.warn,
          target: target,
          message: message,
        );
        break;
      case 'error':
        logEvent(
          file: loc.file,
          line: loc.line,
          level: LogLevel.error,
          target: target,
          message: message,
        );
        break;
      default:
        _logger.i(logMessage);
        logEvent(
          file: loc.file,
          line: loc.line,
          level: LogLevel.info,
          target: target,
          message: message,
        );
    }
  }

  static late Logger _logger;

  /// Initialize Rust logging
  static Future<void> init() async {
    _logger = Logger(printer: PrettyPrinter());
  }

  static void info(String tag, String message) {
    _logMessage(
      LogEntry(
        level: "info",
        message: message,
        timestamp: DateTime.now().millisecondsSinceEpoch as dynamic,
        tag: tag,
      ),
      StackTrace.current,
    );
  }

  static void debug(String tag, String message) {
    _logMessage(
      LogEntry(
        level: "debug",
        message: message,
        timestamp: DateTime.now().millisecondsSinceEpoch as dynamic,
        tag: tag,
      ),
      StackTrace.current,
    );
  }

  static void warn(String tag, String message) {
    _logMessage(
      LogEntry(
        level: "warn",
        message: message,
        timestamp: DateTime.now().millisecondsSinceEpoch as dynamic,
        tag: tag,
      ),
      StackTrace.current,
    );
  }

  static void error(String tag, String message) {
    _logMessage(
      LogEntry(
        level: "error",
        message: message,
        timestamp: DateTime.now().millisecondsSinceEpoch as dynamic,
        tag: tag,
      ),
      StackTrace.current,
    );
  }
}

class LogEntry {
  final String level;
  final String message;
  final int timestamp;
  final String tag;

  LogEntry({
    required this.level,
    required this.message,
    required this.timestamp,
    required this.tag,
  });
}
