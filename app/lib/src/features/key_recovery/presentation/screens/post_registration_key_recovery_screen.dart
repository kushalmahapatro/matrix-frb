import 'package:flutter/material.dart';
import 'package:matrix/src/core/navigation/navigator_service.dart';
import 'package:matrix/src/features/chat_lisitng/presentation/screens/chat_listing_screen.dart';
import 'package:matrix/src/features/key_recovery/presentation/screens/setup_key_recovery_screen.dart';

/// Shown once after successful registration; skip continues to the main app.
class PostRegistrationKeyRecoveryScreen extends StatelessWidget {
  const PostRegistrationKeyRecoveryScreen({super.key});

  void _goHome(BuildContext context) {
    NavigatorService.pushReplacement(context, const ChatListingScreen());
  }

  @override
  Widget build(BuildContext context) {
    return SetupKeyRecoveryScreen(
      showEducation: true,
      showSkip: true,
      onSkip: () => _goHome(context),
      onEnabled: () => _goHome(context),
    );
  }
}
