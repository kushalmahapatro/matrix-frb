import 'package:flutter/material.dart';

abstract class CreateChatRoutes {
  void showSnackBar(BuildContext context, String message);

  Future<bool?> getGroupName(
    BuildContext context,
    TextEditingController groupNameController,
  );

  void goBack(BuildContext context, String chatId);

  /// User chose to open existing DM ([true]), stay ([false]), or dismissed ([null]).
  Future<bool?> showExistingDmDialog(
    BuildContext context, {
    required String otherUserId,
    required String existingRoomId,
  });
}
