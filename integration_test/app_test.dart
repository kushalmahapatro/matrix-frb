import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:matrix/main.dart' as app;
import 'package:matrix/src/core/domain/services/app_config.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Matrix App Integration Tests', () {
    group('Mock Mode Tests', () {
      setUp(() {
        AppConfig.setDataMode(DataMode.mock);
      });

      testWidgets('Complete app flow with mock data', (tester) async {
        await app.main();
        await tester.pumpAndSettle();

        // Test splash screen
        await _testSplashScreen(tester);

        // Test login flow
        await _testLoginFlow(tester);

        // Test chat listing
        await _testChatListing(tester);

        // Test room interaction
        await _testRoomInteraction(tester);

        // Test settings
        await _testSettings(tester);
      });

      testWidgets('Login with invalid credentials', (tester) async {
        await app.main();
        await tester.pumpAndSettle();

        // Wait for splash to complete
        await tester.pumpAndSettle(const Duration(seconds: 4));

        // Try login with invalid credentials
        await _enterCredentials(tester, 'invalid_user', 'wrong_password');
        await _tapLoginButton(tester);

        // Should show error message
        await tester.pumpAndSettle();
        expect(
          find.text('AUTHENTICATION FAILED. CHECK CREDENTIALS.'),
          findsOneWidget,
        );
      });

      testWidgets('Registration flow', (tester) async {
        await app.main();
        await tester.pumpAndSettle();

        // Wait for splash to complete
        await tester.pumpAndSettle(const Duration(seconds: 4));

        // Switch to registration
        await tester.tap(find.text('Don\'t have an account? REGISTER'));
        await tester.pumpAndSettle();

        // Enter registration details
        await _enterCredentials(tester, 'new_user', 'new_password');
        await tester.tap(find.text('REGISTER'));

        // Should succeed and navigate to chat listing
        await tester.pumpAndSettle(const Duration(seconds: 3));
        expect(find.text('MATRIX ROOMS'), findsOneWidget);
      });

      testWidgets('Send message in room', (tester) async {
        await app.main();
        await tester.pumpAndSettle();

        // Complete login flow
        await _completeLoginFlow(tester);

        // Navigate to a room
        await tester.tap(find.text('General Discussion'));
        await tester.pumpAndSettle();

        // Send a message
        await _sendMessage(tester, 'Hello Matrix!');

        // Verify message appears
        expect(find.text('Hello Matrix!'), findsOneWidget);
        expect(find.text('You'), findsOneWidget);
      });

      testWidgets('Error handling in message sending', (tester) async {
        await app.main();
        await tester.pumpAndSettle();

        // Complete login flow
        await _completeLoginFlow(tester);

        // Navigate to a room
        await tester.tap(find.text('General Discussion'));
        await tester.pumpAndSettle();

        // Send a message that triggers error (contains 'error')
        await _sendMessage(tester, 'This will cause an error');

        // Should show error snackbar
        await tester.pumpAndSettle();
        expect(find.text('Failed to send message'), findsOneWidget);
      });
    });

    group('Real Mode Tests', () {
      setUp(() {
        AppConfig.setDataMode(DataMode.real);
      });

      testWidgets('Real mode shows unimplemented errors', (tester) async {
        await app.main();
        await tester.pumpAndSettle();

        // Complete login flow (this should work in mock mode for testing)
        AppConfig.setDataMode(DataMode.mock);
        await _completeLoginFlow(tester);
        AppConfig.setDataMode(DataMode.real);

        // Try to load rooms - should show error
        await tester.pumpAndSettle();
        // The error should be caught and displayed
        expect(find.text('ERROR'), findsOneWidget);
      });
    });
  });
}

// Helper functions
Future<void> _testSplashScreen(WidgetTester tester) async {
  // Verify splash screen elements
  expect(find.text('MATRIX'), findsOneWidget);
  expect(find.text('INITIALIZING...'), findsOneWidget);

  // Wait for splash to complete
  await tester.pumpAndSettle(const Duration(seconds: 4));

  // Should navigate to login screen
  expect(find.text('ENTER THE MATRIX'), findsOneWidget);
}

Future<void> _testLoginFlow(WidgetTester tester) async {
  // Verify login screen elements
  expect(find.text('AUTHENTICATE'), findsOneWidget);
  expect(find.text('HOMESERVER URL'), findsOneWidget);
  expect(find.text('USERNAME'), findsOneWidget);
  expect(find.text('PASSWORD'), findsOneWidget);

  // Enter valid credentials
  await _enterCredentials(tester, 'test_user', 'test_password');

  // Tap login button
  await _tapLoginButton(tester);

  // Should show success message and navigate
  await tester.pumpAndSettle(const Duration(seconds: 3));
  expect(find.text('MATRIX ROOMS'), findsOneWidget);
}

Future<void> _testChatListing(WidgetTester tester) async {
  // Verify chat listing elements
  expect(find.text('MATRIX ROOMS'), findsOneWidget);
  expect(find.text('General Discussion'), findsOneWidget);
  expect(find.text('Development'), findsOneWidget);
  expect(find.text('Alice'), findsOneWidget);

  // Verify unread count badges
  expect(find.text('3'), findsOneWidget); // General Discussion unread count
  expect(find.text('1'), findsOneWidget); // Alice unread count

  // Test create room button
  expect(find.byIcon(Icons.add), findsOneWidget);

  // Test settings button
  expect(find.byIcon(Icons.settings), findsOneWidget);
}

Future<void> _testRoomInteraction(WidgetTester tester) async {
  // Tap on a room
  await tester.tap(find.text('General Discussion'));
  await tester.pumpAndSettle();

  // Verify room screen elements
  expect(find.text('GENERAL DISCUSSION'), findsOneWidget);
  expect(find.text('Welcome to the Matrix!'), findsOneWidget);
  expect(find.text('Neo'), findsOneWidget);

  // Test message input
  expect(find.text('Type your message...'), findsOneWidget);
  expect(find.byIcon(Icons.send), findsOneWidget);

  // Test room info button
  await tester.tap(find.byIcon(Icons.info_outline));
  await tester.pumpAndSettle();

  expect(find.text('ROOM INFO'), findsOneWidget);
  expect(find.text('Room: General Discussion'), findsOneWidget);

  // Close dialog
  await tester.tap(find.text('CLOSE'));
  await tester.pumpAndSettle();
}

Future<void> _testSettings(WidgetTester tester) async {
  // Navigate back to chat listing
  await tester.pageBack();
  await tester.pumpAndSettle();

  // Tap settings button
  await tester.tap(find.byIcon(Icons.settings));
  await tester.pumpAndSettle();

  // Verify settings screen
  expect(find.text('SETTINGS'), findsOneWidget);
  expect(find.text('ACCOUNT'), findsOneWidget);
  expect(find.text('PREFERENCES'), findsOneWidget);
  expect(find.text('ABOUT'), findsOneWidget);

  // Test logout dialog
  await tester.tap(find.text('Logout'));
  await tester.pumpAndSettle();

  expect(find.text('LOGOUT'), findsOneWidget);
  expect(find.text('Are you sure you want to logout?'), findsOneWidget);

  // Cancel logout
  await tester.tap(find.text('CANCEL'));
  await tester.pumpAndSettle();
}

Future<void> _enterCredentials(
  WidgetTester tester,
  String username,
  String password,
) async {
  // Find and fill username field
  final usernameField = find.widgetWithText(
    TextFormField,
    'Enter your Matrix username',
  );
  await tester.enterText(usernameField, username);

  // Find and fill password field
  final passwordField = find.widgetWithText(
    TextFormField,
    'Enter your password',
  );
  await tester.enterText(passwordField, password);

  await tester.pumpAndSettle();
}

Future<void> _tapLoginButton(WidgetTester tester) async {
  await tester.tap(find.text('LOGIN'));
  await tester.pumpAndSettle();
}

Future<void> _completeLoginFlow(WidgetTester tester) async {
  // Wait for splash to complete
  await tester.pumpAndSettle(const Duration(seconds: 4));

  // Enter credentials and login
  await _enterCredentials(tester, 'test_user', 'test_password');
  await _tapLoginButton(tester);

  // Wait for navigation
  await tester.pumpAndSettle(const Duration(seconds: 3));
}

Future<void> _sendMessage(WidgetTester tester, String message) async {
  // Find message input field
  final messageField = find.widgetWithText(TextField, 'Type your message...');
  await tester.enterText(messageField, message);
  await tester.pumpAndSettle();

  // Tap send button
  await tester.tap(find.byIcon(Icons.send));
  await tester.pumpAndSettle();
}
