import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/firebase_options.dart';
import 'package:matrix/src/core/desktop/desktop_conversation_window_app.dart';
import 'package:matrix/src/core/desktop/desktop_incoming_call_main_bridge.dart';
import 'package:matrix/src/core/desktop/desktop_incoming_call_window_app.dart';
import 'package:matrix/src/core/desktop/desktop_incoming_call_window_opener.dart';
import 'package:matrix/src/core/desktop/desktop_ongoing_call_main_bridge.dart';
import 'package:matrix/src/core/desktop/desktop_ongoing_call_window_app.dart';
import 'package:matrix/src/core/desktop/desktop_ongoing_call_window_attacher.dart';
import 'package:matrix/src/core/desktop/desktop_ui_helpers.dart';
import 'package:matrix/src/core/desktop/desktop_window_args.dart';
import 'package:matrix/src/core/desktop/desktop_window_bootstrap.dart';
import 'package:matrix/src/core/desktop/incoming_call_desktop_hooks.dart';
import 'package:matrix/src/core/domain/services/app_config.dart';
import 'package:matrix/src/core/layout/conversation_message_style_preference.dart';
import 'package:matrix/src/core/layout/messaging_layout_preference.dart';
import 'package:matrix/src/features/settings/domain/profile_prefs.dart';
import 'package:matrix/src/core/calls/android_call_launch.dart';
import 'package:matrix/src/core/calls/call_history_store.dart';
import 'package:matrix/src/core/calls/incoming_call_banner_overlay.dart';
import 'package:matrix/src/core/calls/matrix_call_kit_coordinator.dart';
import 'package:matrix/src/core/calls/native_livekit_call_banner.dart';
import 'package:matrix/src/core/file_path_service.dart';
import 'package:matrix/src/core/matrix_app_lifecycle.dart';
import 'package:matrix/src/core/network/network_availability.dart';
import 'package:matrix/src/core/navigation/app_navigation.dart';
import 'package:matrix/src/core/notifications/matrix_notifications_coordinator.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';
import 'package:matrix/src/features/splash/presentation/screen/splash_screen.dart';
import 'package:matrix/src/theme/matrix_theme.dart';
import 'package:matrix/src/theme/theme_provider.dart';
import 'package:matrix_sdk/init.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

/// Firebase Messaging requires [FirebaseMessaging.onBackgroundMessage] to be
/// registered before [runApp]; otherwise iOS/Android may not invoke the background isolate.
bool _needsFirebaseMessagingBeforeRunApp() =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// macOS can deliver key sequences that leave [HardwareKeyboard] out of sync
/// with the embedder (e.g. duplicate [KeyDownEvent] without [KeyUpEvent]),
/// triggering debug asserts. [HardwareKeyboard.syncKeyboardState] re-reads
/// state from the engine. See https://github.com/flutter/flutter/issues/168528
Future<void> _syncMacOsKeyboardFromEngine() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return;
  try {
    await HardwareKeyboard.instance.syncKeyboardState();
  } catch (e, st) {
    debugPrint('HardwareKeyboard.syncKeyboardState failed: $e\n$st');
  }
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(_syncMacOsKeyboardFromEngine());

  // Route auxiliary desktop engines before Firebase: child isolates do not register
  // the same native plugins as the main window (and must not touch Firebase).
  if (!kIsWeb && isDesktopTargetPlatform()) {
    try {
      final wc = await WindowController.fromCurrentEngine().timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException(
          'desktop_multi_window getWindowDefinition',
          const Duration(seconds: 5),
        ),
      );
      if (!DesktopWindowArgs.isMainWindow(wc.arguments)) {
        final conv = DesktopWindowArgs.tryParseConversation(wc.arguments);
        if (conv != null) {
          await runDesktopConversationWindowApp(conv);
          return;
        }
        final incoming = DesktopWindowArgs.tryParseIncomingCall(wc.arguments);
        if (incoming != null) {
          await runDesktopIncomingCallWindowApp(incoming);
          return;
        }
        final ongoing = DesktopWindowArgs.tryParseOngoingCall(wc.arguments);
        if (ongoing != null) {
          await runDesktopOngoingCallWindowApp(ongoing);
          return;
        }
      } else {
        try {
          await windowManager.ensureInitialized();
        } catch (e, st) {
          // After adding window_manager, run `flutter pub get` and `pod install`
          // under macos/ so GeneratedPluginRegistrant includes WindowManagerPlugin.
          debugPrint('window_manager.ensureInitialized: $e\n$st');
        }
        registerDesktopIncomingRingWindowCloser(
          DesktopIncomingCallWindowOpener.closeActive,
        );
        // Do not register [WindowMethodChannel] handlers here: they hit the
        // `desktop_multi_window` embedder channel before [runApp] attaches a valid
        // engine handle (Flutter macOS "merged UI and platform thread" logs
        // `kInvalidArguments` / stuck bootstrap). Registered from [_AppBootstrapState]
        // on the first frame instead.
      }
    } catch (e, st) {
      debugPrint('desktop_multi_window routing: $e\n$st');
    }
  }

  if (_needsFirebaseMessagingBeforeRunApp()) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (e, st) {
      debugPrint('Firebase early init (before runApp): $e\n$st');
    }
  }

  // Show a frame immediately. Awaiting Rust ([MatrixSdk.init]) before [runApp]
  // leaves the macOS window black for the whole load (often mistaken for a hang).
  runDesktopWindowedAppIfEnabled(const _AppBootstrap());
}

/// Loads native backends, then mounts [MyApp].
class _AppBootstrap extends StatefulWidget {
  const _AppBootstrap();

  @override
  State<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<_AppBootstrap> {
  Object? _error;
  bool _ready = false;
  Map<String, dynamic>? _androidCallAcceptPayload;
  bool _androidCallOnlyShell = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_syncMacOsKeyboardFromEngine());
      });
    }
    if (!kIsWeb && isDesktopTargetPlatform()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_registerDesktopMainWindowMethodBridges());
      });
    }
    unawaited(_bootstrap());
  }

  /// [WindowMethodChannel] from `desktop_multi_window` must register after the first
  /// frame so the embedder has a valid engine for `mixin.one/desktop_multi_window`.
  Future<void> _registerDesktopMainWindowMethodBridges() async {
    if (kIsWeb || !isDesktopTargetPlatform()) return;
    try {
      await registerDesktopIncomingCallMainBridge();
      await registerDesktopOngoingCallMainBridge();
    } catch (e, st) {
      debugPrint('_registerDesktopMainWindowMethodBridges: $e\n$st');
    }
  }

  Future<void> _bootstrap() async {
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        _androidCallAcceptPayload =
            await AndroidCallLaunch.takePendingCallAcceptIfAny();
        if (_androidCallAcceptPayload != null) {
          AndroidCallOnlyMode.markActive();
          MatrixCallKitCoordinator.instance
              .scheduleSuppressPluginAcceptDuplicate();
        }
      }

      // Keep MediaKit initialized on every cold start (including Android call-only). It registers
      // global audio plumbing; skipping it coincided with broken uplink/downlink on some devices.
      MediaKit.ensureInitialized();
      await MatrixSdk.init();

      if (!kIsWeb) {
        try {
          if (Firebase.apps.isEmpty) {
            await Firebase.initializeApp(
              options: DefaultFirebaseOptions.currentPlatform,
            );
          }
        } catch (e, st) {
          debugPrint('Firebase.initializeApp failed: $e\n$st');
        }
      }

      if (_androidCallAcceptPayload != null) {
        final sessionOk = await _initMatrixSessionForAndroidCallAccept();
        if (sessionOk) {
          _androidCallOnlyShell = true;
          await ProfilePrefs.instance.refresh(MatrixService().client);
          unawaited(CallHistoryStore.instance.ensureLoaded());
          try {
            await MatrixService().client.startSyncService();
          } catch (e, st) {
            debugPrint('Android call launch startSyncService: $e\n$st');
          }
          MatrixCallKitCoordinator.instance.bindClient(MatrixService().client);
          final id = _androidCallAcceptPayload!['callKitId']?.toString();
          final roomId = _androidCallAcceptPayload!['roomId']?.toString() ?? '';
          final rtc =
              _androidCallAcceptPayload!['rtcEventId']?.toString() ?? '';
          if (id != null &&
              id.isNotEmpty &&
              roomId.isNotEmpty &&
              rtc.isNotEmpty) {
            MatrixCallKitCoordinator.instance.registerCallKitMapping(
              callKitId: id,
              roomId: roomId,
              rtcEventId: rtc,
            );
          }
        } else {
          AndroidCallOnlyMode.markInactive();
          _androidCallAcceptPayload = null;
        }
      }

      if (!mounted) return;
      setState(() => _ready = true);

      if (_androidCallOnlyShell && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_openIncomingCallFromAndroidPayload());
        });
      }
    } catch (e, st) {
      debugPrint('App bootstrap failed: $e\n$st');
      AndroidCallOnlyMode.markInactive();
      if (mounted) setState(() => _error = e);
    }
  }

  Future<bool> _initMatrixSessionForAndroidCallAccept() async {
    try {
      final fp = FilePathService();
      final init = await MatrixService().initialize(
        dbPath: await fp.getDatabasePath(),
        logsPath: await fp.getLogsPath(),
        mediaCachePath: await fp.getMatrixMediaCachePath(),
        showHomeServerForUsername: AppConfig.showHomeServerForUsername,
      );
      var initOk = false;
      init.fold((_) => initOk = true, (_) => initOk = false);
      if (!initOk) return false;
      final logged = await MatrixService().isUserLoggedIn();
      return logged.fold((v) => v, (_) => false);
    } catch (e, st) {
      debugPrint('_initMatrixSessionForAndroidCallAccept: $e\n$st');
      return false;
    }
  }

  Future<void> _openIncomingCallFromAndroidPayload() async {
    final payload = _androidCallAcceptPayload;
    if (payload == null || !mounted) return;
    final roomId = payload['roomId']?.toString() ?? '';
    final roomName = payload['roomName']?.toString() ?? roomId;
    if (roomId.isEmpty) return;
    try {
      await MatrixCallKitCoordinator.instance.openAcceptedIncomingNativeLiveKit(
        client: MatrixService().client,
        roomId: roomId,
        roomName: roomName.isNotEmpty ? roomName : roomId,
      );
    } catch (e, st) {
      debugPrint('_openIncomingCallFromAndroidPayload: $e\n$st');
      AndroidCallOnlyMode.markInactive();
      unawaited(AndroidCallLaunch.finishCallOnlyTask());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Failed to start: $_error'),
            ),
          ),
        ),
      );
    }
    if (!_ready) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.green,
            brightness: Brightness.dark,
          ),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            backgroundColor: const Color(0xFF0D1117),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(
                    color: Colors.lightGreenAccent,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Loading…',
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (_androidCallOnlyShell) {
      return LifeCycleAwareWidget(
        service: MatrixService(),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorKey: AppNavigation.rootNavigatorKey,
          theme: MatrixTheme.getTheme(true, useDesktopChrome: false),
          home: const Scaffold(body: SizedBox.shrink()),
          builder: (context, child) {
            return NativeLiveKitMinimizedCallOverlay(
              child: IncomingCallBannerOverlay(
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
        ),
      );
    }
    return const MyApp();
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<NetworkAvailability>(
          create: (_) => NetworkAvailability(),
        ),
        ChangeNotifierProvider<ThemeProvider>(
          create: (context) => ThemeProvider(),
        ),
        ChangeNotifierProvider<MessagingLayoutPreferenceNotifier>(
          create: (context) => MessagingLayoutPreferenceNotifier()..load(),
        ),
        ChangeNotifierProvider<ConversationMessageStyleNotifier>(
          create: (context) => ConversationMessageStyleNotifier()..load(),
        ),
        ChangeNotifierProvider<ProfilePrefs>.value(
          value: ProfilePrefs.instance,
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          MatrixTheme.updateThemeMode(themeProvider.isDarkMode);
          final desktopChrome = !kIsWeb && isDesktopTargetPlatform();
          return LifeCycleAwareWidget(
            service: MatrixService(),
            child: MaterialApp(
              title: 'Matrix',
              navigatorKey: AppNavigation.rootNavigatorKey,
              theme: MatrixTheme.getTheme(
                themeProvider.isDarkMode,
                useDesktopChrome: desktopChrome,
              ),
              home: const SplashScreen(),
              debugShowCheckedModeBanner: false,
              builder: (context, child) {
                return DesktopOngoingCallWindowAttacher(
                  isDarkMode: themeProvider.isDarkMode,
                  child: NativeLiveKitMinimizedCallOverlay(
                    child: IncomingCallBannerOverlay(
                      child: child ?? const SizedBox.shrink(),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class LifeCycleAwareWidget extends StatefulWidget {
  const LifeCycleAwareWidget({
    super.key,
    required this.child,
    required this.service,
  });
  final Widget child;
  final MatrixService service;

  @override
  State<LifeCycleAwareWidget> createState() => _LifeCycleAwareWidgetState();
}

class _LifeCycleAwareWidgetState extends State<LifeCycleAwareWidget>
    with WidgetsBindingObserver {
  /// Debounced [MatrixClient.restartSyncService] after foreground; cancelled on pause/dispose.
  Timer? _resumeSyncTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _resumeSyncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _scheduleRestartSyncAfterResume() {
    _resumeSyncTimer?.cancel();
    _resumeSyncTimer = Timer(const Duration(milliseconds: 450), () {
      _resumeSyncTimer = null;
      if (!widget.service.isInitialized) return;
      unawaited(_restartSyncSafely());
    });
  }

  Future<void> _restartSyncSafely() async {
    try {
      final authenticated = await widget.service.client.isClientAuthenticated();
      if (!authenticated) {
        debugPrint(
          'restartSyncService after resume: skipped (client not logged in)',
        );
        return;
      }
      await widget.service.client.restartSyncService();
    } catch (e, st) {
      debugPrint('restartSyncService after resume: $e\n$st');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    MatrixAppLifecycle.state = state;
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncMacOsKeyboardFromEngine());
    }
    if (!widget.service.isInitialized) return;
    // Optional battery saver: only when explicitly enabled *and* push registered (Sygnal+FCM).
    // Default is off so sliding sync keeps running while the process is alive — needed because
    // killed-app delivery still depends on a fully working push pipeline.
    if (!kIsWeb &&
        state == AppLifecycleState.paused &&
        AppConfig.pauseSyncOnBackgroundWhenPushOk &&
        MatrixNotificationsCoordinator.instance.shouldPauseBackgroundSync) {
      unawaited(widget.service.client.pauseSyncService());
    }
    // While backgrounded, Android may restrict Wi‑Fi / Doze the radio; sliding sync can then
    // fail DNS or connect until the stack is back. Restarting the instant we get [resumed] races
    // that; a short debounce lets DNS/radio settle first.
    if (state == AppLifecycleState.paused) {
      _resumeSyncTimer?.cancel();
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(
        MatrixNotificationsCoordinator.instance
            .refreshLocalNotificationTapCallbackAfterResume(),
      );
      _scheduleRestartSyncAfterResume();
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
