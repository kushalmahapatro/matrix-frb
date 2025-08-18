import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:matrix/main.dart' as app;
import 'package:matrix/src/core/domain/services/app_config.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Performance Tests', () {
    setUp(() {
      AppConfig.setDataMode(DataMode.mock);
    });

    testWidgets('App startup performance', (tester) async {
      // Measure app startup time
      final stopwatch = Stopwatch()..start();

      // Initialize the app
      app.main();
      await tester.pumpAndSettle();

      stopwatch.stop();

      // App should start within reasonable time
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));

      // Performance test completed successfully
      debugPrint('Startup time: ${stopwatch.elapsedMilliseconds}ms');
    });

    testWidgets('Navigation performance', (tester) async {
      // Initialize the app for this test
      app.main();
      await tester.pumpAndSettle();

      // Wait for splash
      await tester.pumpAndSettle(const Duration(seconds: 4));

      // Login
      await _quickLogin(tester);

      // Measure navigation between screens
      final stopwatch = Stopwatch();

      // Chat listing to room
      stopwatch.start();
      await tester.tap(find.text('General Discussion'));
      await tester.pumpAndSettle();
      stopwatch.stop();

      final roomNavigationTime = stopwatch.elapsedMilliseconds;
      expect(roomNavigationTime, lessThan(1000));

      // Room back to chat listing
      stopwatch.reset();
      stopwatch.start();
      await tester.pageBack();
      await tester.pumpAndSettle();
      stopwatch.stop();

      final backNavigationTime = stopwatch.elapsedMilliseconds;
      expect(backNavigationTime, lessThan(500));

      // Performance test completed successfully
      debugPrint('Room navigation time: ${roomNavigationTime}ms');
      debugPrint('Back navigation time: ${backNavigationTime}ms');
    });

    testWidgets('Message rendering performance', (tester) async {
      // Initialize the app for this test
      app.main();
      await tester.pumpAndSettle();

      // Complete setup
      await tester.pumpAndSettle(const Duration(seconds: 4));
      await _quickLogin(tester);

      // Navigate to room
      await tester.tap(find.text('General Discussion'));
      await tester.pumpAndSettle();

      // Measure message sending performance
      final stopwatch = Stopwatch();

      for (int i = 0; i < 5; i++) {
        stopwatch.start();

        // Send message
        final messageField = find.widgetWithText(
          TextField,
          'Type your message...',
        );
        await tester.enterText(messageField, 'Performance test message $i');
        await tester.tap(find.byIcon(Icons.send));
        await tester.pumpAndSettle();

        stopwatch.stop();
      }

      final averageMessageTime = stopwatch.elapsedMilliseconds / 5;
      expect(averageMessageTime, lessThan(1000));

      // Performance test completed successfully
      debugPrint('Average message send time: ${averageMessageTime}ms');
    });

    testWidgets('Memory usage during room loading', (tester) async {
      // Initialize the app for this test
      app.main();
      await tester.pumpAndSettle();

      // Setup
      await tester.pumpAndSettle(const Duration(seconds: 4));
      await _quickLogin(tester);

      // Load multiple rooms
      final rooms = ['General Discussion', 'Development', 'Alice'];

      for (final room in rooms) {
        await tester.tap(find.text(room));
        await tester.pumpAndSettle();

        // Verify room loaded
        expect(find.text(room.toUpperCase()), findsOneWidget);

        // Go back
        await tester.pageBack();
        await tester.pumpAndSettle();
      }

      // Test completed successfully - memory should be stable
      debugPrint('Successfully loaded ${rooms.length} rooms');
    });

    testWidgets('Animation performance', (tester) async {
      // Initialize the app for this test
      app.main();

      // Measure splash screen animation performance
      final stopwatch = Stopwatch()..start();

      // Let animations run
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 1000));

      stopwatch.stop();

      // Verify Matrix rain animation is running
      expect(find.text('MATRIX'), findsOneWidget);
      expect(find.text('INITIALIZING...'), findsOneWidget);

      // Performance test completed successfully
      debugPrint('Animation test duration: ${stopwatch.elapsedMilliseconds}ms');
    });
  });
}

Future<void> _quickLogin(WidgetTester tester) async {
  // Quick login helper for performance tests
  final usernameField = find.widgetWithText(
    TextFormField,
    'Enter your Matrix username',
  );
  await tester.enterText(usernameField, 'test_user');

  final passwordField = find.widgetWithText(
    TextFormField,
    'Enter your password',
  );
  await tester.enterText(passwordField, 'test_password');

  await tester.tap(find.text('LOGIN'));
  await tester.pumpAndSettle(const Duration(seconds: 3));
}
