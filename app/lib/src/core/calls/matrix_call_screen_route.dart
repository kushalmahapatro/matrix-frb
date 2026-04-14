import 'package:flutter/material.dart';
import 'package:matrix/src/features/conversation/presentation/screens/native_livekit_call_screen.dart';
import 'package:matrix/src/features/conversation/presentation/screens/matrix_incoming_call_answer_screen.dart';

/// Shared transition for full-screen call flows (banner → active call / incoming answer).
Route<T> matrixCallSlideFadeRoute<T>(Widget child) {
  return PageRouteBuilder<T>(
    opaque: true,
    barrierDismissible: false,
    pageBuilder: (context, animation, secondaryAnimation) => child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.05),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(
          opacity: curved,
          child: child,
        ),
      );
    },
    transitionDuration: const Duration(milliseconds: 360),
    reverseTransitionDuration: const Duration(milliseconds: 280),
  );
}

Route<void> matrixNativeLiveKitCallRoute() {
  return matrixCallSlideFadeRoute<void>(const NativeLiveKitCallScreen());
}

Route<void> matrixIncomingAnswerRoute(MatrixIncomingCallAnswerScreen screen) {
  return matrixCallSlideFadeRoute<void>(screen);
}
