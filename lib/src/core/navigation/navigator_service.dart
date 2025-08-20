import 'package:flutter/material.dart';
import 'package:matrix/src/core/screens/error_screen.dart';

class NavigatorService {
  static final NavigatorService _instance = NavigatorService._internal();
  factory NavigatorService() => _instance;
  NavigatorService._internal();

  static void pushReplacement(BuildContext context, Widget page) {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionDuration: const Duration(milliseconds: 800),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  static Future<T?> push<T extends Object?>(BuildContext context, Widget page) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionDuration: const Duration(milliseconds: 800),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  static void showErrorScreen(BuildContext context, Exception exception) {
    push(context, ErrorScreen(exception: exception));
  }

  static void pop(BuildContext context) {
    Navigator.of(context).pop();
  }
}
