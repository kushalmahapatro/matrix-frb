import 'package:flutter/material.dart';
import 'package:matrix/src/features/splash/presentation/screen/splash_screen.dart';
import 'package:matrix/src/core/logging_service.dart';
import 'package:matrix/src/rust/api/platform.dart';
import 'package:matrix/src/rust/api/tracing.dart';
import 'package:matrix/src/rust/frb_generated.dart';
import 'package:matrix/src/theme/theme_provider.dart';
import 'package:matrix/src/theme/matrix_theme.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize Flutter Rust Bridge with custom logging
  await RustLib.init();

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
          return MaterialApp(
            title: 'Matrix Terminal',
            theme: MatrixTheme.getTheme(themeProvider.isDarkMode),
            home: const SplashScreen(),
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}
