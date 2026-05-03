import 'package:flutter/material.dart';

abstract class SplashRoutes {
  void navigateToLoginScreen(BuildContext context);

  void navigateToChatScreen(BuildContext context);

  void navigateToErrorScreen(BuildContext context, Exception exception);
}
