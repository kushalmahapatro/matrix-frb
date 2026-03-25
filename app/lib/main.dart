import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:matrix/src/core/domain/services/app_config.dart';
import 'package:matrix/src/core/matrix_app_lifecycle.dart';
import 'package:matrix/src/core/notifications/matrix_notifications_coordinator.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';
import 'package:matrix/src/features/splash/presentation/screen/splash_screen.dart';
import 'package:matrix/src/theme/matrix_theme.dart';
import 'package:matrix/src/theme/theme_provider.dart';
import 'package:matrix_sdk/init.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await MatrixSdk.init();

  if (!kIsWeb) {
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (e, st) {
      debugPrint('Firebase.initializeApp failed: $e\n$st');
    }
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => ThemeProvider(),
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          MatrixTheme.updateThemeMode(themeProvider.isDarkMode);
          return LifeCycleAwareWidget(
            service: MatrixService(),
            child: MaterialApp(
              title: 'Matrix Terminal',
              theme: MatrixTheme.getTheme(themeProvider.isDarkMode),
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
