import 'package:elementary/elementary.dart';
import 'package:flutter/material.dart';
import 'package:matrix/src/core/navigation/navigator_service.dart';
import 'package:matrix/src/core/presentation/widgets/terminal_container.dart';
import 'package:matrix/src/features/auth/domain/models/auth_state.dart';
import 'package:matrix/src/features/auth/domain/services/auth_service.dart';
import 'package:matrix/src/features/auth/presentation/screens/login_screen_wm.dart';
import 'package:matrix/src/features/auth/routes/auth_route.dart';
import 'package:matrix/src/features/chat_lisitng/presentation/screens/chat_listing_screen.dart';
import 'package:matrix/src/theme/matrix_theme.dart';

LoginScreenWM loginScreenWMFactory(BuildContext context) {
  return LoginScreenWM(LoginScreenModel(AuthService()));
}

class LoginScreen extends ElementaryWidget<LoginScreenWM> implements AuthRoute {
  const LoginScreen({super.key}) : super(loginScreenWMFactory);

  @override
  Widget build(LoginScreenWM wm) {
    return TerminalScreen(
      showAppBar: false,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: wm.formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.max,
              children: [
                const SizedBox(height: 60),

                // Matrix Logo
                const Text(
                  "MATRIX",
                  textAlign: TextAlign.center,
                  style: MatrixTheme.logoStyle,
                ),

                const SizedBox(height: 20),

                // Subtitle
                const Text(
                  "ENTER THE MATRIX",
                  textAlign: TextAlign.center,
                  style: MatrixTheme.subtitleStyle,
                ),

                const SizedBox(height: 60),

                // Login Form Container
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: MatrixTheme.containerDecoration,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 20),

                      // Username
                      TerminalTextField(
                        controller: wm.usernameController,
                        label: 'USERNAME',
                        hint: 'Enter your Matrix username',
                        icon: Icons.person,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Username is required';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 20),

                      // Password
                      TerminalTextField(
                        controller: wm.passwordController,
                        label: 'PASSWORD',
                        hint: 'Enter your password',
                        icon: Icons.lock,
                        isPassword: true,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Password is required';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 30),

                      // Status Message
                      statusWidget(wm),

                      // Login or Register Button Button
                      ValueListenableBuilder(
                        valueListenable: wm.formData,
                        builder: (context, formData, child) {
                          return AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child:
                                !formData.isRegistration
                                    ? loginButton(wm)
                                    : registerButton(wm),
                          );
                        },
                      ),

                      const SizedBox(height: 16),

                      togleAuthMode(wm),
                    ],
                  ),
                ),

                // Switch between Login and Register
                const SizedBox(height: 100),

                // Footer
                const Text(
                  "CHOOSE YOUR REALITY",
                  textAlign: TextAlign.center,
                  style: MatrixTheme.captionStyle,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget statusWidget(LoginScreenWM wm) {
    return ValueListenableBuilder(
      valueListenable: wm.authState,
      builder: (context, value, child) {
        return value is AuthStateError
            ? Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                border: Border.all(
                  color: MatrixTheme.getStatusColor(
                    (wm.authState.value as AuthStateError).message,
                  ),
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                (wm.authState.value as AuthStateError).message,
                style: MatrixTheme.getStatusStyle(
                  (wm.authState.value as AuthStateError).message,
                ),
                textAlign: TextAlign.center,
              ),
            )
            : const SizedBox.shrink();
      },
    );
  }

  Widget togleAuthMode(LoginScreenWM wm) {
    return ValueListenableBuilder(
      valueListenable: wm.formData,
      builder: (context, formData, child) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: InkWell(
            onTap: wm.toggleRegistration,
            child:
                formData.isRegistration
                    ? Text(
                      key: ValueKey('AlreadyHaveAccount'),
                      'Already have an account?',
                      textAlign: TextAlign.center,
                    )
                    : Text(
                      key: ValueKey('DontHaveAccount'),
                      'Don\'t have an account?',
                      textAlign: TextAlign.center,
                    ),
          ),
        );
      },
    );
  }

  SizedBox registerButton(LoginScreenWM wm) {
    return SizedBox(
      key: ValueKey('RegistrationButton'),
      height: 50,
      child: ElevatedButton(
        onPressed:
            wm.authState.value is AuthStateLoading ? null : wm.authenticate,
        style: MatrixTheme.primaryButtonStyle,
        child:
            wm.authState.value is AuthStateLoading
                ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      MatrixTheme.colors.onSurface,
                    ),
                    strokeWidth: 2,
                  ),
                )
                : const Text('REGISTER', style: MatrixTheme.buttonStyle),
      ),
    );
  }

  SizedBox loginButton(LoginScreenWM wm) {
    return SizedBox(
      key: ValueKey('LoginButton'),
      height: 50,
      child: ElevatedButton(
        onPressed:
            wm.authState.value is AuthStateLoading ? null : wm.authenticate,
        style: MatrixTheme.primaryButtonStyle,
        child:
            wm.authState.value is AuthStateLoading
                ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      MatrixTheme.colors.onSurface,
                    ),
                    strokeWidth: 2,
                  ),
                )
                : const Text('LOGIN', style: MatrixTheme.buttonStyle),
      ),
    );
  }

  @override
  void navigateToChatListingScreen(BuildContext context) {
    NavigatorService.push(context, const ChatListingScreen());
  }
}
