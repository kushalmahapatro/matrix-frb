import 'package:elementary/elementary.dart';
import 'package:flutter/material.dart';
import 'package:matrix/src/core/navigation/navigator_service.dart';
import 'package:matrix/src/core/presentation/widgets/terminal_container.dart';
import 'package:matrix/src/features/auth/domain/models/auth_state.dart';
import 'package:matrix/src/features/auth/presentation/screens/login_screen_wm.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';
import 'package:matrix/src/features/auth/routes/auth_route.dart';
import 'package:matrix/src/features/chat_lisitng/presentation/screens/chat_listing_screen.dart';

LoginScreenWM loginScreenWMFactory(BuildContext context) {
  return LoginScreenWM(LoginScreenModel(MatrixService()));
}

class LoginScreen extends ElementaryWidget<LoginScreenWM> implements AuthRoute {
  const LoginScreen({super.key}) : super(loginScreenWMFactory);

  @override
  Widget build(LoginScreenWM wm) {
    return TerminalScreen(
      showAppBar: false,
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: wm.formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    const SizedBox(height: 60),
                    Text(
                      'MATRIX',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 8,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'ENTER THE MATRIX',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 60),
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: theme.colorScheme.primary,
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(4),
                        color: theme.colorScheme.surfaceContainerHighest,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 20),
                          ValueListenableBuilder(
                            valueListenable: wm.formData,
                            builder: (context, formData, child) {
                              if (!formData.isRegistration) {
                                return const SizedBox.shrink();
                              }
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  TerminalTextField(
                                    controller: wm.displayNameController,
                                    label: 'DISPLAY NAME',
                                    hint: 'How others will see you',
                                    icon: Icons.badge,
                                    validator: wm.validateDisplayName,
                                  ),
                                  const SizedBox(height: 20),
                                ],
                              );
                            },
                          ),

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
                          _statusWidget(context, wm),
                          ValueListenableBuilder(
                            valueListenable: wm.formData,
                            builder: (context, formData, child) {
                              return AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                child: !formData.isRegistration
                                    ? _loginButton(context, wm)
                                    : _registerButton(context, wm),
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          _toggleAuthMode(wm),
                        ],
                      ),
                    ),
                    const SizedBox(height: 100),
                    Text(
                      'CHOOSE YOUR REALITY',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _statusWidget(BuildContext context, LoginScreenWM wm) {
    final theme = Theme.of(context);
    return ValueListenableBuilder(
      valueListenable: wm.authState,
      builder: (context, value, child) {
        if (value is! AuthStateError) return const SizedBox.shrink();
        final message = (wm.authState.value as AuthStateError).message;
        final isError = message.contains('ERROR');
        return Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            border: Border.all(
              color: isError
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isError
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
            ),
            textAlign: TextAlign.center,
          ),
        );
      },
    );
  }

  Widget _toggleAuthMode(LoginScreenWM wm) {
    return ValueListenableBuilder(
      valueListenable: wm.formData,
      builder: (context, formData, child) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: InkWell(
            onTap: wm.toggleRegistration,
            child: formData.isRegistration
                ? Text(
                    key: const ValueKey('AlreadyHaveAccount'),
                    'Already have an account?',
                    textAlign: TextAlign.center,
                  )
                : Text(
                    key: const ValueKey('DontHaveAccount'),
                    'Don\'t have an account?',
                    textAlign: TextAlign.center,
                  ),
          ),
        );
      },
    );
  }

  SizedBox _registerButton(BuildContext context, LoginScreenWM wm) {
    final theme = Theme.of(context);
    return SizedBox(
      key: const ValueKey('RegistrationButton'),
      height: 50,
      child: ElevatedButton(
        onPressed: wm.authState.value is AuthStateLoading
            ? null
            : wm.authenticate,
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
        ),
        child: wm.authState.value is AuthStateLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    theme.colorScheme.onPrimary,
                  ),
                  strokeWidth: 2,
                ),
              )
            : Text(
                'REGISTER',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onPrimary,
                ),
              ),
      ),
    );
  }

  SizedBox _loginButton(BuildContext context, LoginScreenWM wm) {
    final theme = Theme.of(context);
    return SizedBox(
      key: const ValueKey('LoginButton'),
      height: 50,
      child: ElevatedButton(
        onPressed: wm.authState.value is AuthStateLoading
            ? null
            : wm.authenticate,
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
        ),
        child: wm.authState.value is AuthStateLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    theme.colorScheme.onPrimary,
                  ),
                  strokeWidth: 2,
                ),
              )
            : Text(
                'LOGIN',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onPrimary,
                ),
              ),
      ),
    );
  }

  @override
  void navigateToChatListingScreen(BuildContext context) {
    NavigatorService.pushReplacement(context, const ChatListingScreen());
  }
}
