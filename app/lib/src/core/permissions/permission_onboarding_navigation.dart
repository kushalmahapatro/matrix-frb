import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:matrix/src/core/navigation/navigator_service.dart';
import 'package:matrix/src/core/permissions/permission_onboarding_prefs.dart';
import 'package:matrix/src/core/permissions/permission_onboarding_status.dart';
import 'package:matrix/src/features/chat_lisitng/presentation/screens/chat_listing_screen.dart';
import 'package:matrix/src/features/onboarding/presentation/screens/permission_onboarding_screen.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';

/// After sync/session is ready, either shows permission onboarding or the chat list.
Future<void> navigateHomeAfterSessionReady(BuildContext context) async {
  if (!context.mounted) return;
  if (kIsWeb) {
    await PermissionOnboardingPrefs.setCompleted();
    if (!context.mounted) return;
    unawaited(MatrixService().startMatrixNotificationsIfReady());
    NavigatorService.pushReplacement(context, const ChatListingScreen());
    return;
  }

  final done = await PermissionOnboardingPrefs.isCompleted();
  if (!context.mounted) return;
  if (done) {
    unawaited(MatrixService().startMatrixNotificationsIfReady());
    NavigatorService.pushReplacement(context, const ChatListingScreen());
    return;
  }

  final allGranted = await PermissionOnboardingStatuses.allRequiredGranted();
  if (!context.mounted) return;
  if (allGranted) {
    await PermissionOnboardingPrefs.setCompleted();
    if (!context.mounted) return;
    unawaited(MatrixService().startMatrixNotificationsIfReady());
    NavigatorService.pushReplacement(context, const ChatListingScreen());
    return;
  }

  NavigatorService.pushReplacement(
    context,
    const PermissionOnboardingScreen(),
  );
}
