import 'package:flutter/material.dart';

abstract class CreateChatRoutes {
  void showSnackBar(BuildContext context, String message);

  Future<bool?> getGroupName(
    BuildContext context,
    TextEditingController groupNameController,
  );

  void goBack(BuildContext context, String chatId);
}
