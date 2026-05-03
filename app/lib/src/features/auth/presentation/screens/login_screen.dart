import 'dart:async';

import 'package:elementary/elementary.dart';
import 'package:flutter/material.dart';
import 'package:matrix/src/core/navigation/navigator_service.dart';
import 'package:matrix/src/core/permissions/permission_onboarding_navigation.dart';
import 'package:matrix/src/core/presentation/widgets/terminal_container.dart';
import 'package:matrix/src/features/auth/domain/models/auth_state.dart';
import 'package:matrix/src/features/auth/presentation/screens/login_screen_wm.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';
import 'package:matrix/src/features/auth/routes/auth_route.dart';
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
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          // Side-by-side needs width and enough height; otherwise a single centered
          // column avoids stretched/pinned corners on macOS windows and phones.
          final useSideBySide = w >= 840 && h >= 520;
          final form = Form(
            key: wm.formKey,
            child: _authFormCard(context, wm),
          );

          final horizontalPad = w >= 600 ? 40.0 : 24.0;
          final verticalPad = h >= 600 ? 32.0 : 20.0;
          final maxContentW = useSideBySide ? 920.0 : 440.0;

          final content = useSideBySide
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: _loginBranding(
                            context,
                            theme,
                            alignStart: true,
                          ),
                        ),
                        SizedBox(width: w >= 960 ? 56 : 40),
                        Expanded(child: form),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'CHOOSE YOUR REALITY',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _loginBranding(context, theme, alignStart: false),
                    const SizedBox(height: 32),
                    form,
                    const SizedBox(height: 36),
                    Text(
                      'CHOOSE YOUR REALITY',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                );

          return ClipRect(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPad,
                  vertical: verticalPad,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: 0,
                    minHeight: (h - verticalPad * 2).clamp(0.0, double.infinity),
                  ),
                  child: Align(
                    alignment: Alignment.center,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxContentW),
                      child: content,
                    ),
                  ),
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
          AnimatedBuilder(
            animation: Listenable.merge([wm.authState, wm.formData]),
            builder: (context, child) {
              final formData = wm.formData.value;
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
    unawaited(navigateHomeAfterSessionReady(context));
  }

  @override
  void navigateToPostRegistrationRecovery(BuildContext context) {
    NavigatorService.pushReplacement(
      context,
      const PostRegistrationKeyRecoveryScreen(),
    );
  }
}
