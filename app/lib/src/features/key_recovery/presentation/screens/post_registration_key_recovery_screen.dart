import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/src/core/permissions/permission_onboarding_navigation.dart';
import 'package:matrix/src/features/key_recovery/presentation/screens/setup_key_recovery_screen.dart';

/// Shown once after successful registration; skip continues to the main app.
class PostRegistrationKeyRecoveryScreen extends StatelessWidget {
  const PostRegistrationKeyRecoveryScreen({super.key});

  void _goHome(BuildContext context) {
    unawaited(navigateHomeAfterSessionReady(context));
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
