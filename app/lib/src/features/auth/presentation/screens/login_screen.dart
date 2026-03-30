import 'package:elementary/elementary.dart';
import 'package:flutter/material.dart';
import 'package:matrix/src/core/navigation/navigator_service.dart';
import 'package:matrix/src/core/presentation/widgets/terminal_container.dart';
import 'package:matrix/src/features/auth/domain/models/auth_state.dart';
import 'package:matrix/src/features/auth/presentation/screens/login_screen_wm.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';
import 'package:matrix/src/features/auth/routes/auth_route.dart';
import 'package:matrix/src/features/chat_lisitng/presentation/screens/chat_listing_screen.dart';
import 'package:matrix/src/features/key_recovery/presentation/screens/post_registration_key_recovery_screen.dart';

LoginScreenWM loginScreenWMFactory(BuildContext context) {
  return LoginScreenWM(LoginScreenModel(MatrixService()));
}

class LoginScreen extends ElementaryWidget<LoginScreenWM> implements AuthRoute {
  const LoginScreen({super.key}) : super(loginScreenWMFactory);

  @override
  Widget build(LoginScreenWM wm) {
    return TerminalScreen(
      showAppBar: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final theme = Theme.of(context);
          final wide = constraints.maxWidth >= 840;
          final form = Form(
            key: wm.formKey,
            child: _authFormCard(context, wm),
          );
          if (wide) {
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 1040,
                  minHeight: constraints.maxHeight > 400
                      ? constraints.maxHeight
                      : 400,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        flex: 5,
                        child: _loginBranding(context, theme, alignStart: true),
                      ),
                      const SizedBox(width: 48),
                      Expanded(
                        flex: 6,
                        child: SingleChildScrollView(
                          child: form,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 40),
                    _loginBranding(context, theme, alignStart: false),
                    const SizedBox(height: 40),
                    form,
                    const SizedBox(height: 48),
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

  Widget _loginBranding(
    BuildContext context,
    ThemeData theme, {
    required bool alignStart,
  }) {
    final align = alignStart ? TextAlign.start : TextAlign.center;
    final cross = alignStart
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.center;
    return Column(
      crossAxisAlignment: cross,
      children: [
        Text(
          'MATRIX',
          textAlign: align,
          style: theme.textTheme.headlineLarge?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.bold,
            letterSpacing: 8,
            fontSize: alignStart ? 42 : null,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'ENTER THE MATRIX',
          textAlign: align,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        if (alignStart) ...[
          const SizedBox(height: 24),
          Text(
            'Sign in to sync encrypted rooms, files, and voice — '
            'same account on mobile and desktop.',
            textAlign: TextAlign.start,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _authFormCard(BuildContext context, LoginScreenWM wm) {
    final theme = Theme.of(context);
    return Container(
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
          const SizedBox(height: 8),
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
          ValueListenableBuilder(
            valueListenable: wm.formData,
            builder: (context, formData, child) {
              return TerminalTextField(
                controller: wm.passwordController,
                label: 'PASSWORD',
                hint: 'Enter your password',
                icon: Icons.lock,
                isPassword: true,
                obscureText: !formData.showPassword,
                suffixIcon: formData.showPassword
                    ? Icons.visibility_off
                    : Icons.visibility,
                onSuffixPressed: wm.togglePasswordVisibility,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Password is required';
                  }
                  return null;
                },
              );
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

  @override
  void navigateToPostRegistrationRecovery(BuildContext context) {
    NavigatorService.pushReplacement(
      context,
      const PostRegistrationKeyRecoveryScreen(),
    );
  }
}
