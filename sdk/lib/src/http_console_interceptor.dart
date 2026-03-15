// Copyright 2025 The Matrix.org Foundation C.I.C.
//
// Dart-based HTTP "interceptor" that shows Matrix SDK HTTP traffic in the dev
// console and in Dart DevTools Network View (via package:http_profile).
// Mirrors the flow used by package:rhttp (createDevToolsProfile + trackCustomResponse).
// Data comes from the Rust tracing stream; this module parses and formats it.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:http_profile/http_profile.dart';

import 'http_log.dart';

/// Parsed fields from a single Matrix SDK HTTP trace line (span "send").
/// Used for console logging and in-memory HTTP log (request/response as one entry when complete).
class HttpTraceEntry {
  HttpTraceEntry({
    this.method,
    this.uri,
    this.requestId,
    this.status,
    this.responseSize,
    this.requestDuration,
    this.requestSize,
    this.sentryEventId,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final String? method;
  final String? uri;
  final String? requestId;
  final int? status;
  final String? responseSize;
  final String? requestDuration;
  final String? requestSize;
  final String? sentryEventId;
  final DateTime timestamp;

  bool get hasResponse => status != null;

  @override
  String toString() {
    return 'HttpTraceEntry(method: $method, uri: $uri, requestId: $requestId, status: $status, responseSize: $responseSize, requestDuration: $requestDuration, requestSize: $requestSize, sentryEventId: $sentryEventId)';
  }
}

/// In-memory HTTP log (last [maxEntries] entries). Always available in debug;
/// use [lastHttpLogEntries] to read and e.g. show in a debug overlay.
const int _maxHttpLogEntries = 100;
final List<HttpTraceEntry> _httpLogEntries = [];

/// Returns a copy of the last HTTP log entries (newest last). Use for debugging
/// and to show API flow in-app (e.g. debug screen).
List<HttpTraceEntry> get lastHttpLogEntries =>
    List<HttpTraceEntry>.from(_httpLogEntries);

/// Clears the in-memory HTTP log.
void clearHttpLog() {
  _httpLogEntries.clear();
}

/// Dumps the last [count] HTTP log entries to the debug console (same format as
/// live logging). Use from DevTools console or a debug button to inspect API flow.
void dumpLastHttpLog({int count = 20}) {
  final list = lastHttpLogEntries;
  final start = list.length > count ? list.length - count : 0;
  for (var i = start; i < list.length; i++) {
    _printEntryToConsole(list[i], store: false);
  }
}

// Match span block: send{ key=value, ... } (may appear as "spans: send{...}" or "spans: foo > send{...}")
final RegExp _spanSendBlock = RegExp(r'send\s*\{([^}]*)\}');

bool _didLogProfileNull = false;

/// Parses a tracing log line and returns parsed HTTP fields if it's a Matrix SDK
/// HTTP "send" span line; otherwise null.
HttpTraceEntry? parseHttpTraceLine(String line) {
  if (!line.contains(matrixSdkHttpClientTarget)) return null;
  final match = _spanSendBlock.firstMatch(line);
  if (match == null) return null;
  final content = match.group(1)!;
  final map = <String, String>{};
  // Parse key=value or key="value". Unquoted value stops at space so we don't consume the next key (e.g. method=POST uri="...").
  final keyValue = RegExp(r'(\w+)=(?:"([^"]*)"|([^,\s]+))');
  for (final kv in keyValue.allMatches(content)) {
    final key = kv.group(1)!;
    final value = kv.group(2) ?? kv.group(3)?.trim() ?? '';
    map[key] = value;
  }
  if (map.isEmpty) return null;
  return HttpTraceEntry(
    method: map['method'],
    uri: map['uri'],
    requestId: map['request_id'],
    status: map['status'] != null ? int.tryParse(map['status']!) : null,
    responseSize: map['response_size'],
    requestDuration: map['request_duration'],
    requestSize: map['request_size'],
    sentryEventId: map['sentry_event_id'],
  );
}

/// Parses request_duration string (e.g. "123ms", "2.5s", or "Duration { secs: 0, nanos: 123000000 }") to milliseconds.
int? _parseDurationMs(String? s) {
  if (s == null || s.isEmpty) return null;
  s = s.trim();
  if (s.endsWith('ms')) {
    final n = int.tryParse(s.substring(0, s.length - 2).trim());
    return n;
  }
  if (s.endsWith('s') || s.endsWith('m') || s.endsWith('h')) {
    final num = double.tryParse(s.substring(0, s.length - 1).trim());
    if (num == null) return null;
    if (s.endsWith('s')) return (num * 1000).round();
    if (s.endsWith('m')) return (num * 60 * 1000).round();
    if (s.endsWith('h')) return (num * 3600 * 1000).round();
  }
  final durationMatch = RegExp(
    r'Duration\s*\{\s*secs:\s*(\d+)\s*,\s*nanos:\s*(\d+)',
  ).firstMatch(s);
  if (durationMatch != null) {
    final secs = int.tryParse(durationMatch.group(1) ?? '0') ?? 0;
    final nanos = int.tryParse(durationMatch.group(2) ?? '0') ?? 0;
    return secs * 1000 + (nanos ~/ 1000000);
  }
  return int.tryParse(s);
}

/// Builds response headers for DevTools (same shape as rhttp's trackCustomResponse).
Map<String, List<String>> _responseHeadersFromEntry(HttpTraceEntry e) {
  final map = <String, List<String>>{};
  if (e.responseSize != null) map['x-matrix-response-size'] = [e.responseSize!];
  if (e.requestId != null) map['x-matrix-request-id'] = [e.requestId!];
  if (e.requestDuration != null) {
    map['x-matrix-duration'] = [e.requestDuration!];
  }
  return map;
}

/// Pushes a completed HTTP trace entry to Dart DevTools Network View.
/// Flow matches rhttp's dev_tools: create profile, requestData.close(), then
/// responseData (statusCode, headersListValues), then responseData.close().
/// Must await so the profile is fully finalized for DevTools.
Future<void> _pushToDevTools(HttpTraceEntry e) async {
  if (e.method == null || e.uri == null) return;
  // Ensure profiling is on (DevTools or other code may reset it).
  HttpClientRequestProfile.profilingEnabled = true;
  final durationMs = _parseDurationMs(e.requestDuration);
  final endTime = DateTime.now();
  final startTime = durationMs != null
      ? endTime.subtract(Duration(milliseconds: durationMs))
      : endTime;
  final profile = HttpClientRequestProfile.profile(
    requestStartTime: startTime,
    requestMethod: e.method!,
    requestUri: e.uri!,
  );
  if (profile == null) {
    if (!_didLogProfileNull) {
      _didLogProfileNull = true;
      debugPrint(
        'Matrix HTTP: DevTools profile not available (profiling disabled or release build). '
        'Ensure you run in debug and DevTools is connected.',
      );
    }
    return;
  }
  profile.connectionInfo = {'package': 'matrix_sdk'};
  await profile.requestData.close(startTime);
  if (e.status != null) {
    profile.responseData.statusCode = e.status!;
    profile.responseData.headersListValues = _responseHeadersFromEntry(e);
    profile.responseData.startTime = startTime;
    await profile.responseData.close(endTime);
  } else {
    await profile.responseData.closeWithError('No response', endTime);
  }
}

/// Prints one HTTP trace entry as a REQUEST/RESPONSE block. If [store] is true,
/// also appends to [lastHttpLogEntries].
void _printEntryToConsole(HttpTraceEntry e, {bool store = true}) {
  if (store) {
    _httpLogEntries.add(e);
    if (_httpLogEntries.length > _maxHttpLogEntries) {
      _httpLogEntries.removeAt(0);
    }
  }

  final sep = '────────────────────────────────────────────────────────────';
  debugPrint(sep);
  debugPrint('Matrix HTTP  REQUEST');
  debugPrint('  method:     ${e.method ?? "-"}');
  debugPrint('  uri:        ${e.uri ?? "-"}');
  debugPrint('  request_id: ${e.requestId ?? "-"}');
  if (e.requestSize != null) debugPrint('  body size:  ${e.requestSize}');
  debugPrint(sep);
  debugPrint('Matrix HTTP  RESPONSE');
  debugPrint('  status:     ${e.status ?? "-"}');
  if (e.responseSize != null) debugPrint('  body size:  ${e.responseSize}');
  if (e.requestDuration != null) debugPrint('  duration:   ${e.requestDuration}');
  if (e.sentryEventId != null) debugPrint('  sentry_id:  ${e.sentryEventId}');
  debugPrint(sep);
}

void _printHttpEntry(HttpTraceEntry e) => _printEntryToConsole(e, store: true);

/// Optional workaround: subscribes to Matrix SDK HTTP trace logs and pushes
/// them to the dev console and DevTools Network (via Rust tracing, not rhttp).
///
/// **Raw rhttp client logs** only appear for HTTP made through the Dart rhttp
/// API (e.g. [RhttpClient.request]). When Matrix uses the same [RequestClient]
/// via [ClientConfig.rhttpClient], requests run in Rust and do not go through
/// the Dart rhttp layer, so they do not appear as rhttp logs in DevTools.
///
/// Call this only if you want Matrix SDK requests to show in the console/Network
/// tab via this tracing-based bridge. No-op in release.
StreamSubscription<String>? installHttpConsoleInterceptor() {
  if (!kDebugMode) return null;
  // Ensure profile() returns a non-null profile so entries show in DevTools Network tab.
  try {
    HttpClientRequestProfile.profilingEnabled = true;
  } catch (_) {
    // dart:io may be unavailable (e.g. on web); DevTools Network will not show Matrix HTTP.
  }
  return subscribeHttpLogs().listen((line) {
    final entry = parseHttpTraceLine(line);
    if (entry == null) return;
    _printHttpEntry(entry);
    // Run on the main isolate so the profile's isolateId matches what DevTools shows.
    SchedulerBinding.instance.scheduleFrameCallback((_) async {
      await _pushToDevTools(entry);
    });
  });
}
