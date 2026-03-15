// Copyright 2025 The Matrix.org Foundation C.I.C.
//
// Interceptor for Matrix SDK HTTP requests that run through the rhttp client.
// Use when creating the RhttpClient that you pass to ClientConfig.rhttpClient
// so these callbacks run before each request (and optionally log to DevTools).

import 'package:flutter/foundation.dart';
import 'package:http_profile/http_profile.dart';
import 'package:matrix_sdk/src/rhttp/src/interceptor/interceptor.dart';
import 'package:matrix_sdk/src/rhttp/src/model/request.dart';

/// Interceptor that logs Matrix HTTP requests to the console and optionally
/// to the Dart DevTools Network tab.
///
/// When the rhttp client is created with this interceptor and passed to
/// [ClientConfig.rhttpClient], each Matrix API request will:
/// - In debug: print method + URL to the console
/// - If [enableDevTools] is true: create a profile so the request appears
///   in DevTools > Network (request only; response is not attached).
class MatrixHttpLoggingInterceptor extends Interceptor {
  /// Whether to push request entries to the DevTools Network tab.
  final bool enableDevTools;

  MatrixHttpLoggingInterceptor({this.enableDevTools = true});

  @override
  Future<InterceptorResult<HttpRequest>> beforeRequest(HttpRequest request) async {
    if (kDebugMode) {
      debugPrint('Matrix HTTP  ${request.method.value} ${request.url}');
    }

    if (enableDevTools) {
      try {
        HttpClientRequestProfile.profilingEnabled = true;
        final profile = HttpClientRequestProfile.profile(
          requestStartTime: DateTime.now(),
          requestMethod: request.method.value,
          requestUri: request.url,
        );
        if (profile != null) {
          profile.connectionInfo = {'package': 'matrix_sdk'};
          await profile.requestData.close(DateTime.now());
          // Response is not available in this bridge; profile will show as no response
          await profile.responseData.closeWithError('(response in Rust)', DateTime.now());
        }
      } catch (_) {
        // DevTools / http_profile may be unavailable (e.g. on web or release)
      }
    }

    return Interceptor.next(request);
  }
}
