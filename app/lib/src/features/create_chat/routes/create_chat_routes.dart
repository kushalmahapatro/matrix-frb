import 'package:flutter/material.dart';
import 'package:matrix/src/theme/matrix_theme.dart';

/// Snackbar style for [showCreateChatSnackBar] / [CreateChatRoutes.showSnackBar].
enum CreateChatSnackKind {
  error,
  success,
  neutral,
}

/// Shared snackbar styling (works after [Navigator.pop] if the same [ScaffoldMessenger] is used).
void showCreateChatSnackBar(
  ScaffoldMessengerState messenger,
  String message, {
  CreateChatSnackKind kind = CreateChatSnackKind.error,
}) {
  late final Color bg;
  late final Color fg;
  late final IconData icon;
  switch (kind) {
    case CreateChatSnackKind.success:
      bg = MatrixTheme.terminalDarkGreen;
      fg = MatrixTheme.matrixLightGreen;
      icon = Icons.done;
    case CreateChatSnackKind.neutral:
      bg = MatrixTheme.terminalBorder;
      fg = MatrixTheme.matrixLightGreen;
      icon = Icons.info_outline_rounded;
    case CreateChatSnackKind.error:
      bg = MatrixTheme.errorRed;
      fg = Colors.white;
      icon = Icons.error_outline_rounded;
  }

  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: fg.withValues(alpha: 0.45), width: 1),
      ),
      backgroundColor: bg,
      duration: kind == CreateChatSnackKind.success
          ? const Duration(seconds: 3)
          : const Duration(seconds: 4),
      content: Row(
        children: [
          Icon(icon, color: fg, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w600,
                fontSize: 14,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

abstract class CreateChatRoutes {
  void showSnackBar(
    BuildContext context,
    String message, {
    CreateChatSnackKind kind = CreateChatSnackKind.error,
  });

  void goBack(BuildContext context, String chatId);

  /// User chose to open existing DM ([true]), stay ([false]), or dismissed ([null]).
  Future<bool?> showExistingDmDialog(
    BuildContext context, {
    required String otherUserId,
    required String otherUserDisplayLabel,
    required String existingRoomId,
  });
}
