import 'dart:async';

import 'package:elementary/elementary.dart';
import 'package:flutter/material.dart';
import 'package:graphx/graphx.dart';
import 'package:matrix/src/core/desktop/desktop_ui_helpers.dart';
import 'package:matrix/src/core/file_path_service.dart';
import 'package:matrix/src/core/navigation/navigator_service.dart';
import 'package:matrix/src/features/auth/presentation/screens/login_screen.dart';
import 'package:matrix/src/core/permissions/permission_onboarding_navigation.dart';
import 'package:matrix/src/features/splash/domain/models/matrix_characters.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';
import 'package:matrix/src/features/splash/presentation/screen/splash_screen_wm.dart';
import 'package:matrix/src/features/splash/presentation/widgets/matrix_rain_drawing_screen.dart';
import 'package:matrix/src/features/splash/routes/splash_routes.dart';
import 'package:matrix/src/theme/matrix_theme.dart';

SplashScreenWM splashScreenWMFactory(BuildContext context) {
  return SplashScreenWM(SplashScreenModel(MatrixService(), FilePathService()));
}

class SplashScreen extends ElementaryWidget<SplashScreenWM>
    implements SplashRoutes {
  const SplashScreen({super.key}) : super(splashScreenWMFactory);

  @override
  Widget build(SplashScreenWM wm) {
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        // Scaffold gives the scene bounded constraints; without it, GraphX can
        // layout at 0×0 on some routes/embedders (black screen + GraphX warning).
        return Scaffold(
          backgroundColor: theme.colorScheme.surface,
          // GraphX / SceneBuilderWidget often paints nothing on desktop embedders
          // (looks like a black screen) even when constraints are valid; use Flutter
          // chrome here. Mobile keeps the Matrix rain.
          body: !kIsWeb && isDesktopTargetPlatform()
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        color: MatrixTheme.matrixGreen,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Loading…',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final w = constraints.maxWidth;
                    final h = constraints.maxHeight;
                    if (!constraints.hasBoundedWidth ||
                        !constraints.hasBoundedHeight ||
                        w <= 0 ||
                        h <= 0) {
                      // Empty placeholder on dark scaffold reads as a black screen.
                      return Center(
                        child: CircularProgressIndicator(
                          color: MatrixTheme.matrixGreen,
                        ),
                      );
                    }
                    return SizedBox(
                      width: w,
                      height: h,
                      child: SceneBuilderWidget(
                        builder: () => SceneController(
                          back: MatrixRainDrawingScene(
                            matrixCharacters,
                            backgroundColor: theme.colorScheme.surface,
                            textColor: MatrixTheme.matrixGreen,
                          ),
                        ),
                        autoSize: false,
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  @override
  void navigateToChatScreen(BuildContext context) {
    unawaited(navigateHomeAfterSessionReady(context));
  }

  @override
  void navigateToErrorScreen(BuildContext context, Exception exception) {
    NavigatorService.showErrorScreen(context, exception);
  }

  @override
  void navigateToLoginScreen(BuildContext context) {
    NavigatorService.pushReplacement(context, const LoginScreen());
  }
}
