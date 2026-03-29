import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:matrix/src/core/desktop/desktop_conversation_window_app.dart';
import 'package:matrix/src/core/desktop/desktop_ui_helpers.dart';
import 'package:matrix/src/core/desktop/desktop_window_args.dart';
import 'package:matrix/src/core/desktop/desktop_window_bootstrap.dart';
import 'package:matrix/src/core/domain/services/app_config.dart';
import 'package:matrix/src/core/layout/conversation_message_style_preference.dart';
import 'package:matrix/src/core/layout/messaging_layout_preference.dart';
import 'package:matrix/src/features/settings/domain/profile_prefs.dart';
import 'package:matrix/src/core/matrix_app_lifecycle.dart';
import 'package:matrix/src/core/notifications/matrix_notifications_coordinator.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';
import 'package:matrix/src/features/splash/presentation/screen/splash_screen.dart';
import 'package:matrix/src/theme/matrix_theme.dart';
import 'package:matrix/src/theme/theme_provider.dart';
import 'package:matrix_sdk/init.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && isDesktopTargetPlatform()) {
    try {
      final wc = await WindowController.fromCurrentEngine();
      if (!DesktopWindowArgs.isMainWindow(wc.arguments)) {
        final conv = DesktopWindowArgs.tryParseConversation(wc.arguments);
        if (conv != null) {
          await runDesktopConversationWindowApp(conv);
          return;
        }
      }
    } catch (e, st) {
      debugPrint('desktop_multi_window routing: $e\n$st');
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

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      MediaKit.ensureInitialized();
      await MatrixSdk.init();

      if (!kIsWeb) {
        try {
          await Firebase.initializeApp();
          FirebaseMessaging.onBackgroundMessage(
            firebaseMessagingBackgroundHandler,
          );
        } catch (e, st) {
          debugPrint('Firebase.initializeApp failed: $e\n$st');
        }
      }

      if (mounted) setState(() => _ready = true);
    } catch (e, st) {
      debugPrint('App bootstrap failed: $e\n$st');
      if (mounted) setState(() => _error = e);
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
                  const CircularProgressIndicator(color: Colors.lightGreenAccent),
                  const SizedBox(height: 20),
                  Text(
                    'Loading…',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white70,
                        ),
                  ),
                ],
              ),
            ),
          ),
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
        ChangeNotifierProvider<ThemeProvider>(
          create: (context) => ThemeProvider(),
        ),
        ChangeNotifierProvider<MessagingLayoutPreferenceNotifier>(
          create: (context) => MessagingLayoutPreferenceNotifier()..load(),
        ),
        ChangeNotifierProvider<ConversationMessageStyleNotifier>(
          create: (context) => ConversationMessageStyleNotifier()..load(),
        ),
        ChangeNotifierProvider<ProfilePrefs>.value(value: ProfilePrefs.instance),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          MatrixTheme.updateThemeMode(themeProvider.isDarkMode);
          final desktopChrome =
              !kIsWeb && isDesktopTargetPlatform();
          return LifeCycleAwareWidget(
            service: MatrixService(),
            child: MaterialApp(
              title: 'Matrix',
              theme: MatrixTheme.getTheme(
                themeProvider.isDarkMode,
                useDesktopChrome: desktopChrome,
              ),
              home: const SplashScreen(),
              debugShowCheckedModeBanner: false,
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
      await widget.service.client.restartSyncService();
    } catch (e, st) {
      debugPrint('restartSyncService after resume: $e\n$st');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    MatrixAppLifecycle.state = state;
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
      _scheduleRestartSyncAfterResume();
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
