import 'package:flutter/material.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';
import 'package:matrix/src/features/splash/presentation/screen/splash_screen.dart';
import 'package:matrix/src/theme/matrix_theme.dart';
import 'package:matrix/src/theme/theme_provider.dart';
import 'package:matrix_sdk/init.dart';
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MatrixSdk.init();

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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && widget.service.isInitialized) {
      widget.service.client.restartSyncService();
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
