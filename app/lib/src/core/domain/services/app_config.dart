import 'package:flutter/foundation.dart';

class AppConfig {
  /// Matrix homeserver base URL. Override with `--dart-define-from-file=...` and key `HOMESERVER`.
  static Uri get homeserverUrl => Uri.parse(
    const String.fromEnvironment(
      'HOMESERVER',
      defaultValue: 'https://matrix.org',
    ),
  );

  static String? proxyUrl = String.fromEnvironment(
    'PROXY_URL',
    defaultValue: '',
  );

  /// Optional registration token. Set via `REGISTRATION_TOKEN` in dart-define-from-file (empty = disabled).
  static String? get registrationToken {
    const v = String.fromEnvironment('REGISTRATION_TOKEN', defaultValue: '');
    if (v.isEmpty) return null;
    return v;
  }

  /// When false, Rust shortens Matrix IDs for UI (`@user` only). Splash passes this into `MatrixService.initialize`.
  static bool showHomeServerForUsername = false;

  /// Sygnal (or compatible) HTTP notify URL for [MatrixClient.registerPusher].
  /// Example: `https://your-sygnal.example/_matrix/push/v1/notify`.
  static String get matrixPushGatewayUrl =>
      const String.fromEnvironment('MATRIX_PUSH_GATEWAY_URL', defaultValue: '');

  /// Sygnal `app_id` for your FCM/APNs app block (must match `sygnal.yaml`).
  ///
  /// Platform-specific defines (e.g. separate Sygnal `apps:` for iOS vs Android):
  /// - [MATRIX_PUSH_APP_ID_IOS] — iOS and macOS
  /// - [MATRIX_PUSH_APP_ID_ANDROID] — Android
  ///
  /// Web and other targets get an empty id (push registration is skipped).
  static String get matrixPushAppId {
    const ios = String.fromEnvironment(
      'MATRIX_PUSH_APP_ID_IOS',
      defaultValue: '',
    );
    const android = String.fromEnvironment(
      'MATRIX_PUSH_APP_ID_ANDROID',
      defaultValue: '',
    );
    if (kIsWeb) return '';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return ios;
      case TargetPlatform.android:
        return android;
      default:
        return '';
    }
  }

  /// Sygnal notify URL for the **VoIP** Matrix pusher (PushKit / separate `app_id` from FCM/APNs alert).
  ///
  /// iOS only in practice; empty means the app does not register a VoIP pusher.
  static String get matrixVoipPushGatewayUrl =>
      const String.fromEnvironment('MATRIX_VOIP_PUSH_GATEWAY_URL', defaultValue: '');

  /// Sygnal `app_id` for the VoIP push app block (must match `sygnal.yaml`, e.g. `*.voip`).
  static String get matrixVoipPushAppIdIos => const String.fromEnvironment(
        'MATRIX_VOIP_PUSH_APP_ID_IOS',
        defaultValue: 'dev.inve.matrixchat.ios.voip',
      );

  /// True when this build was compiled with a non-empty [matrixPushGatewayUrl] and
  /// [matrixPushAppId] for the current platform. TestFlight/IPA builds made without
  /// `--dart-define-from-file=...` will be false and the app will not register a Matrix pusher.
  static bool get isMatrixPushConfigPresent {
    return matrixPushGatewayUrl.trim().isNotEmpty &&
        matrixPushAppId.trim().isNotEmpty;
  }

  /// When true and Matrix pusher registration succeeded, the app may stop sliding sync while
  /// minimized (battery saver). Requires working FCM + Sygnal delivery; default **false** so
  /// notifications still work from sync while the process is alive.
  static bool get pauseSyncOnBackgroundWhenPushOk => const bool.fromEnvironment(
    'MATRIX_PAUSE_SYNC_ON_BACKGROUND',
    defaultValue: false,
  );

  // --- Native LiveKit (Rust `livekit` crate + FRB; LiveKit Cloud OK) ---

  /// WebSocket URL from the LiveKit Cloud dashboard, e.g. `wss://myproj.livekit.cloud`.
  static String get livekitWebSocketUrl =>
      const String.fromEnvironment('LIVEKIT_URL', defaultValue: '');

  /// **Dev only:** paste a short-lived access JWT from LiveKit CLI / dashboard.
  /// Production should use [livekitTokenFetchUrl] instead (no secrets in the app).
  static String get livekitDevAccessToken =>
      const String.fromEnvironment('LIVEKIT_DEV_ACCESS_TOKEN', defaultValue: '');

  /// HTTPS endpoint that returns JSON `{ "token": "...", "url": "wss://..."? }`.
  /// `matrix_room_id` and `voice_only` are sent as query params.
  static String get livekitTokenFetchUrl =>
      const String.fromEnvironment('LIVEKIT_TOKEN_FETCH_URL', defaultValue: '');

  /// Base URL of the LiveKit token API (POST JSON to `/token`), e.g. `https://livekit.inve.dev`.
  /// See [LiveKitTokenService] for the request body shape.
  static String get livekitTokenApiUrl =>
      const String.fromEnvironment('LIVEKIT_TOKEN_API_URL', defaultValue: '');

  /// When `true`, native LiveKit calls are disabled (call UI will show an error).
  static bool get disableNativeLiveKit =>
      const bool.fromEnvironment('DISABLE_NATIVE_LIVEKIT', defaultValue: false);

  /// Native path is available (not on web): dev token + [livekitWebSocketUrl], **or** POST
  /// [livekitTokenApiUrl] (response may supply `url`), **or** legacy GET [livekitTokenFetchUrl]
  /// plus [livekitWebSocketUrl].
  static bool get isNativeLiveKitConfigurable {
    if (disableNativeLiveKit || kIsWeb) return false;
    final ws = livekitWebSocketUrl.trim();
    final dev = livekitDevAccessToken.trim();
    final postApi = livekitTokenApiUrl.trim();
    final getFetch = livekitTokenFetchUrl.trim();
    if (dev.isNotEmpty) return ws.isNotEmpty;
    if (postApi.isNotEmpty) return true;
    if (getFetch.isNotEmpty) return ws.isNotEmpty;
    return false;
  }
}
