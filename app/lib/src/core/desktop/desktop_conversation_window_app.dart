import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/src/core/desktop/desktop_matrix_quick_start.dart';
import 'package:matrix/src/core/desktop/desktop_window_args.dart';
import 'package:matrix/src/core/layout/conversation_message_style_preference.dart';
import 'package:matrix/src/features/settings/domain/profile_prefs.dart';
import 'package:matrix/src/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';
import 'package:matrix/src/theme/matrix_theme.dart';
import 'package:provider/provider.dart';

/// Second-engine entry: same DB as main window — possible SQLite contention;
/// acceptable for experiments / light use.
Future<void> runDesktopConversationWindowApp(
  DesktopConversationWindowArgs args,
) async {
  final init = await initMatrixDesktopIsolate();
  if (!init.isSuccess()) {
    final err = init.exceptionOrNull();
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Matrix init failed: $err'),
            ),
          ),
        ),
      ),
    );
    return;
  }

  try {
    await MatrixService().client.startSyncService();
  } catch (e, st) {
    debugPrint('conversation window startSyncService: $e\n$st');
  }

  unawaited(ProfilePrefs.instance.refresh(MatrixService().client));

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ConversationMessageStyleNotifier>(
          create: (_) => ConversationMessageStyleNotifier()..load(),
        ),
        ChangeNotifierProvider<ProfilePrefs>.value(value: ProfilePrefs.instance),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: MatrixTheme.getTheme(
          args.isDarkMode,
          useDesktopChrome: true,
        ),
        home: ConversationScreen(
          roomId: args.roomId,
          roomName: args.roomName,
          status: args.status,
          implyLeading: false,
        ),
      ),
    ),
  );
}
