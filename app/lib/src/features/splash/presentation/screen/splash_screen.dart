import 'package:elementary/elementary.dart';
import 'package:flutter/material.dart';
import 'package:graphx/graphx.dart';
import 'package:matrix/src/core/file_path_service.dart';
import 'package:matrix/src/core/navigation/navigator_service.dart';
import 'package:matrix/src/features/auth/presentation/screens/login_screen.dart';
import 'package:matrix/src/features/chat_lisitng/presentation/screens/chat_listing_screen.dart';
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
          // Explicit size from layout avoids GraphX's first-frame 0×0 warning when
          // the embedder reports an empty size before the initial layout pass.
          body: LayoutBuilder(
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
    NavigatorService.pushReplacement(context, const ChatListingScreen());
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
