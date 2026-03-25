class AppConfig {
  /// Matrix homeserver base URL. Override with `--dart-define-from-file=...` and key `HOMESERVER`.
  static Uri get homeserverUrl => Uri.parse(
    const String.fromEnvironment(
      'HOMESERVER',
      defaultValue: 'https://marix.org',
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
  static String get matrixPushAppId =>
      const String.fromEnvironment('MATRIX_PUSH_APP_ID', defaultValue: '');

  /// When true and Matrix pusher registration succeeded, the app may stop sliding sync while
  /// minimized (battery saver). Requires working FCM + Sygnal delivery; default **false** so
  /// notifications still work from sync while the process is alive.
  static bool get pauseSyncOnBackgroundWhenPushOk => const bool.fromEnvironment(
        'MATRIX_PAUSE_SYNC_ON_BACKGROUND',
        defaultValue: false,
      );
}
