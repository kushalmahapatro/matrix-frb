import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:matrix/src/core/domain/services/app_config.dart';
import 'package:matrix_sdk/matrix_sdk.dart' show MatrixClient;

/// Result of resolving LiveKit Cloud credentials for the Rust-backed native LiveKit session.
class LiveKitJoinCredentials {
  LiveKitJoinCredentials({required this.url, required this.token});

  final String url;
  final String token;
}

/// Parsed JSON from `POST {tokenApi}/token` (e.g. [livekit.inve.dev](https://livekit.inve.dev)).
class LiveKitTokenResponse {
  LiveKitTokenResponse({required this.token, this.url});

  final String token;
  final String? url;

  factory LiveKitTokenResponse.fromJson(Map<String, dynamic> map) {
    String? pickStr(List<String> keys) {
      for (final k in keys) {
        final v = map[k];
        if (v is String && v.isNotEmpty) return v;
      }
      return null;
    }

    final token = pickStr(['token', 'access_token', 'accessToken', 'jwt']);
    if (token == null) {
      throw FormatException('LiveKit token JSON missing token field: $map');
    }
    final url = pickStr([
      'url',
      'serverUrl',
      'server_url',
      'livekitUrl',
      'livekit_url',
      'ws_url',
      'websocketUrl',
      'wss_url',
    ]);
    return LiveKitTokenResponse(token: token, url: url);
  }
}

/// Obtains a LiveKit access token: **dev define**, **POST token API** ([AppConfig.livekitTokenApiUrl]),
/// or legacy **GET** ([AppConfig.livekitTokenFetchUrl]).
class LiveKitTokenService {
  LiveKitTokenService._();

  static Future<LiveKitJoinCredentials?> resolve({
    required MatrixClient matrixClient,
    required String matrixRoomId,
    required bool voiceOnly,
    required bool joinExisting,
  }) async {
    final dev = AppConfig.livekitDevAccessToken.trim();
    final wsFallback = AppConfig.livekitWebSocketUrl.trim();

    if (dev.isNotEmpty) {
      if (wsFallback.isEmpty) return null;
      return LiveKitJoinCredentials(url: wsFallback, token: dev);
    }

    final api = AppConfig.livekitTokenApiUrl.trim();
    if (api.isNotEmpty) {
      return _resolvePostTokenApi(
        apiBase: api,
        matrixRoomId: matrixRoomId,
        wsFallback: wsFallback,
        matrixClient: matrixClient,
      );
    }

    final fetch = AppConfig.livekitTokenFetchUrl.trim();
    if (fetch.isEmpty) return null;
    if (wsFallback.isEmpty) return null;

    final baseUri = Uri.parse(fetch);
    final qp = Map<String, String>.from(baseUri.queryParameters);
    qp['matrix_room_id'] = matrixRoomId;
    qp['voice_only'] = voiceOnly ? '1' : '0';
    qp['join_existing'] = joinExisting ? '1' : '0';
    final uri = baseUri.replace(queryParameters: qp);

    final resp = await http
        .get(uri)
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      return null;
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) return null;
    final map = Map<String, dynamic>.from(decoded);
    String? pickStr(List<String> keys) {
      for (final k in keys) {
        final v = map[k];
        if (v is String && v.isNotEmpty) return v;
      }
      return null;
    }

    final token = pickStr(['token', 'accessToken', 'access_token']);
    if (token == null) return null;
    final url = pickStr([
          'url',
          'serverUrl',
          'livekitUrl',
          'ws_url',
          'websocketUrl',
        ]) ??
        wsFallback;
    return LiveKitJoinCredentials(url: url, token: token);
  }

  static Future<LiveKitJoinCredentials?> _resolvePostTokenApi({
    required String apiBase,
    required String matrixRoomId,
    required String wsFallback,
    required MatrixClient matrixClient,
  }) async {
    final identity = await matrixClient.loggedInUserId();
    if (identity == null || identity.isEmpty) return null;

    String? displayName;
    try {
      displayName = await matrixClient.getDisplayName();
    } catch (_) {}

    final base = apiBase.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/token');

    final body = <String, dynamic>{
      'room_name': matrixRoomId,
      'identity': identity,
      if (displayName != null && displayName.trim().isNotEmpty)
        'name': displayName.trim(),
    };

    final resp = await http
        .post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      return null;
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) return null;
    final parsed = LiveKitTokenResponse.fromJson(
      Map<String, dynamic>.from(decoded),
    );

    final url = (parsed.url != null && parsed.url!.trim().isNotEmpty)
        ? parsed.url!.trim()
        : wsFallback;
    if (url.isEmpty) return null;

    return LiveKitJoinCredentials(url: url, token: parsed.token);
  }
}
