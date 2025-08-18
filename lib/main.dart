import 'package:flutter/material.dart';
import 'package:matrix/src/extensions/context_extension.dart';
import 'package:matrix/src/logging_service.dart';
import 'package:matrix/src/rust/api/platform.dart';
import 'package:matrix/src/rust/api/tracing.dart';
import 'package:matrix/src/splash_screen.dart';
import 'package:matrix/src/rust/frb_generated.dart';
import 'package:matrix/src/theme/theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;

Uri homeserverUrl = Uri.parse('http://10.44.1.85:8008');
// Uri homeserverUrl = Uri.parse(
// 'https://hugh-prefer-bring-entry.trycloudflare.com',
// );
// const String homeserverUrl = 'https://server.serverplatform.ae';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize Flutter Rust Bridge with custom logging
  await RustLib.init();

  // Initialize Rust logging
  await LoggingService.initializeLogging();
  final String databasesPath = await getDatabasesPath();

  try {
    await initPlatform(
      config: TracingConfiguration(
        logLevel: LogLevel.trace,
        traceLogPacks: TraceLogPacks.values,
        extraTargets: [],
        writeToStdoutOrSystem: true,
        writeToFiles: TracingFileConfiguration(
          path: '$databasesPath${path.separator}logs',
          filePrefix: 'matrix',
          fileSuffix: '.log',
        ),
      ),
      useLightweightTokioRuntime: false,
    );
  } catch (e) {
    debugPrint(e.toString());
  }

  // Test Rust logging
  debugPrint('[FLUTTER] Initializing Matrix app with Rust logging...');

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
            title: 'Matrix Flutter App',
            theme: themeProvider.theme,
            home: const SplashScreen(),
            // const EnhancedMatrixWidget(),
          );
        },
      ),
    );
  }
}

class MatrixDemoPage extends StatefulWidget {
  const MatrixDemoPage({super.key});

  @override
  State<MatrixDemoPage> createState() => _MatrixDemoPageState();
}

class _MatrixDemoPageState extends State<MatrixDemoPage> {
  String _statusMessage = 'Ready to test Matrix SDK integration';

  @override
  void initState() {
    super.initState();
    _testBasicFunctionality();
  }

  void _testBasicFunctionality() async {
    setState(() {
      _statusMessage = 'Testing basic functionality...';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Matrix SDK + Flutter Rust Bridge'),
        backgroundColor: context.colors.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status message
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_statusMessage, style: const TextStyle(fontSize: 16)),
            ),

            // Demo section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Matrix SDK Integration Demo',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'This app demonstrates Matrix SDK integration with Flutter using Flutter Rust Bridge instead of UniFFI.',
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Key Features:',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('• Matrix client authentication'),
                    const Text('• Room management'),
                    const Text('• Message sending and receiving'),
                    const Text('• Real-time sync'),
                    const SizedBox(height: 16),
                    const Text(
                      'Test Result:',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Instructions
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Next Steps',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'To complete the Matrix SDK integration:',
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    const Text('1. Add Matrix client login UI'),
                    const Text('2. Implement room listing'),
                    const Text('3. Add message sending/receiving'),
                    const Text('4. Handle real-time updates'),
                    const Text('5. Add error handling and retry logic'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
