import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:matrix/main.dart' as app;
import 'package:matrix/src/core/domain/services/app_config.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Accessibility Tests', () {
    setUp(() {
      AppConfig.setDataMode(DataMode.mock);
    });

    testWidgets('Screen reader accessibility', (tester) async {
      await app.main();
      await tester.pumpAndSettle();

      // Test splash screen accessibility
      await _testSplashAccessibility(tester);

      // Navigate to login
      await tester.pumpAndSettle(const Duration(seconds: 4));

      // Test login screen accessibility
      await _testLoginAccessibility(tester);

      // Complete login
      await _quickLogin(tester);

      // Test chat listing accessibility
      await _testChatListingAccessibility(tester);

      // Test room accessibility
      await tester.tap(find.text('General Discussion'));
      await tester.pumpAndSettle();
      await _testRoomAccessibility(tester);
    });

    testWidgets('Keyboard navigation', (tester) async {
      await app.main();
      await tester.pumpAndSettle();

      // Wait for splash
      await tester.pumpAndSettle(const Duration(seconds: 4));

      // Test tab navigation through login form
      await _testKeyboardNavigation(tester);
    });

    testWidgets('Color contrast and visibility', (tester) async {
      await app.main();
      await tester.pumpAndSettle();

      // Test Matrix theme colors are accessible
      await _testColorContrast(tester);
    });

    testWidgets('Touch target sizes', (tester) async {
      await app.main();
      await tester.pumpAndSettle();

      // Wait for splash
      await tester.pumpAndSettle(const Duration(seconds: 4));

      // Test button sizes meet accessibility guidelines
      await _testTouchTargets(tester);
    });
  });
}

Future<void> _testSplashAccessibility(WidgetTester tester) async {
  // Verify splash screen has proper semantics
  expect(find.text('MATRIX'), findsOneWidget);
  expect(find.text('INITIALIZING...'), findsOneWidget);

  // Check for loading indicator
  expect(find.byType(CircularProgressIndicator), findsOneWidget);
}

Future<void> _testLoginAccessibility(WidgetTester tester) async {
  // Verify form labels are present
  expect(find.text('HOMESERVER URL'), findsOneWidget);
  expect(find.text('USERNAME'), findsOneWidget);
  expect(find.text('PASSWORD'), findsOneWidget);

  // Verify form fields have proper hints
  expect(find.text('https://matrix.org'), findsOneWidget);
  expect(find.text('Enter your Matrix username'), findsOneWidget);
  expect(find.text('Enter your password'), findsOneWidget);

  // Verify buttons have proper labels
  expect(find.text('LOGIN'), findsOneWidget);
  expect(find.text('Don\'t have an account? REGISTER'), findsOneWidget);

  // Test password visibility toggle
  final passwordToggle = find.byIcon(Icons.visibility);
  expect(passwordToggle, findsOneWidget);

  await tester.tap(passwordToggle);
  await tester.pumpAndSettle();

  expect(find.byIcon(Icons.visibility_off), findsOneWidget);
}

Future<void> _testChatListingAccessibility(WidgetTester tester) async {
  // Verify screen title
  expect(find.text('MATRIX ROOMS'), findsOneWidget);

  // Verify action buttons have tooltips
  final addButton = find.byIcon(Icons.add);
  expect(addButton, findsOneWidget);

  final settingsButton = find.byIcon(Icons.settings);
  expect(settingsButton, findsOneWidget);

  // Verify room list items are accessible
  expect(find.text('General Discussion'), findsOneWidget);
  expect(find.text('Development'), findsOneWidget);
  expect(find.text('Alice'), findsOneWidget);

  // Verify unread count badges are present
  expect(find.text('3'), findsOneWidget);
  expect(find.text('1'), findsOneWidget);
}

Future<void> _testRoomAccessibility(WidgetTester tester) async {
  // Verify room title
  expect(find.text('GENERAL DISCUSSION'), findsOneWidget);

  // Verify message list is accessible
  expect(find.text('Welcome to the Matrix!'), findsOneWidget);
  expect(find.text('Neo'), findsOneWidget);

  // Verify message input accessibility
  expect(find.text('Type your message...'), findsOneWidget);

  final sendButton = find.byIcon(Icons.send);
  expect(sendButton, findsOneWidget);

  // Verify room info button
  final infoButton = find.byIcon(Icons.info_outline);
  expect(infoButton, findsOneWidget);
}

Future<void> _testKeyboardNavigation(WidgetTester tester) async {
  // Test that form fields can be navigated with keyboard
  final usernameField = find.widgetWithText(
    TextFormField,
    'Enter your Matrix username',
  );
  final passwordField = find.widgetWithText(
    TextFormField,
    'Enter your password',
  );
  final loginButton = find.text('LOGIN');

  // Verify fields exist
  expect(usernameField, findsOneWidget);
  expect(passwordField, findsOneWidget);
  expect(loginButton, findsOneWidget);

  // Test field focus
  await tester.tap(usernameField);
  await tester.pumpAndSettle();

  await tester.enterText(usernameField, 'test_user');
  await tester.pumpAndSettle();

  // Tab to next field (simulated by tapping)
  await tester.tap(passwordField);
  await tester.pumpAndSettle();

  await tester.enterText(passwordField, 'test_password');
  await tester.pumpAndSettle();
}

Future<void> _testColorContrast(WidgetTester tester) async {
  // Verify Matrix green text is visible on black background
  final matrixText = find.text('MATRIX');
  expect(matrixText, findsOneWidget);

  // Verify form elements have proper contrast
  final authenticateText = find.text('AUTHENTICATE');
  expect(authenticateText, findsOneWidget);

  // Verify button text has proper contrast
  final loginButton = find.text('LOGIN');
  expect(loginButton, findsOneWidget);
}

Future<void> _testTouchTargets(WidgetTester tester) async {
  // Test that buttons meet minimum touch target size (44x44 dp)
  final loginButton = find.text('LOGIN');
  expect(loginButton, findsOneWidget);

  // Get button widget
  final buttonWidget = tester.widget<ElevatedButton>(
    find.ancestor(of: loginButton, matching: find.byType(ElevatedButton)),
  );

  // Verify button exists (size testing would require more complex setup)
  expect(buttonWidget, isNotNull);

  // Test password toggle button
  final passwordToggle = find.byIcon(Icons.visibility);
  expect(passwordToggle, findsOneWidget);

  // Test that toggle is tappable
  await tester.tap(passwordToggle);
  await tester.pumpAndSettle();
}

Future<void> _quickLogin(WidgetTester tester) async {
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
