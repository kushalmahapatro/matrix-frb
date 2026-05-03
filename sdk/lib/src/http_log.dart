// Copyright 2025 The Matrix.org Foundation C.I.C.
//
// Use this module to capture/intercept all HTTP logs from the Matrix SDK
// (similar to rhttp's DevTools / Network tab: https://codeberg.org/Tienisto/rhttp).

import 'package:matrix_sdk/src/bindings/logger/platform.dart' as platform;

/// Target string for Matrix SDK HTTP client logs. Used for filtering.
const String matrixSdkHttpClientTarget = 'matrix_sdk::http_client';

/// Stream of HTTP-only tracing logs from the Matrix SDK (request/response, etc.).
///
/// Use this to capture all HTTP traffic for a "Network" tab or DevTools-style viewer.
/// Log lines include the target `matrix_sdk::http_client` and, at trace level,
/// span fields such as uri, method, request_id, status, request_duration.
///
/// For more detail (URI, method, status, duration), set trace level for
/// `matrix_sdk::http_client` when initializing (e.g. add [TraceLogPacks.matrixSdkHttp]
/// to [TracingConfiguration.traceLogPacks] if available after codegen).
///
/// Must be called after [platform.initPlatform].
Stream<String> subscribeHttpLogs() {
  return platform.subscribeTracingLogs().where(
        (line) => line.contains(matrixSdkHttpClientTarget),
      );
}
