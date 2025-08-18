import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/src/features/create_chat/create_room_screen.dart';
import 'package:matrix/src/theme/theme_provider.dart';
import 'package:provider/provider.dart';

void main() {
  group('CreateRoomScreen', () {
    testWidgets('should display basic UI elements', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider(
            create: (_) => ThemeProvider(),
            child: const CreateRoomScreen(),
          ),
        ),
      );

      // Verify basic UI elements are displayed
      expect(find.text('DIRECT CHAT'), findsOneWidget);
      expect(find.text('GROUP CHAT'), findsOneWidget);
      expect(find.text('ROOM TYPE'), findsOneWidget);
      expect(find.text('ADD PARTICIPANTS'), findsOneWidget);
      expect(find.text('CREATE DIRECT CHAT'), findsOneWidget);
    });
  });
}
