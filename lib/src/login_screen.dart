import 'package:flutter/material.dart';
import 'package:matrix/src/extensions/context_extension.dart';
import 'package:matrix/src/rust/api/matrix_client.dart';
import 'package:matrix/src/home_screen.dart';
import 'package:matrix/src/theme/matrix_theme.dart';
import 'package:matrix/src/theme/theme_provider.dart';
import 'package:provider/provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _homeserverController = TextEditingController(
    text: 'http://localhost:8008',
  );
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String _statusMessage = '';
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _homeserverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    MatrixTheme.updatePlatformBrightness(context);

    super.didChangePlatformBrightness();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _statusMessage = 'CONNECTING TO MATRIX...';
    });

    try {
      final success = await login(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;

      if (success) {
        setState(() {
          _statusMessage = 'AUTHENTICATION SUCCESSFUL. REDIRECTING...';
        });

        // Wait a moment for user to see success message
        await Future.delayed(const Duration(seconds: 1));

        if (!mounted) return;

        // Navigate to home screen
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder:
                (context, animation, secondaryAnimation) => const HomeScreen(),
            transitionDuration: const Duration(milliseconds: 800),
            transitionsBuilder: (
              context,
              animation,
              secondaryAnimation,
              child,
            ) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      } else {
        setState(() {
          _statusMessage = 'AUTHENTICATION FAILED. CHECK CREDENTIALS.';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _statusMessage = 'ERROR: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      // Homeserver URL
                      _buildMatrixTextField(
                        controller: _homeserverController,
                        label: 'HOMESERVER URL',
                        hint: 'http://localhost:8008',
                        icon: Icons.dns,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Homeserver URL is required';
                          }
                          final uri = Uri.tryParse(value);
                          if (uri == null || !uri.hasScheme) {
                            return 'Invalid URL format';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 20),

                      // Username
                      _buildMatrixTextField(
                        controller: _usernameController,
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
                      _buildMatrixTextField(
                        controller: _passwordController,
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
                      if (_statusMessage.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: MatrixTheme.getStatusColor(_statusMessage),
                              width: 1,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _statusMessage,
                            style: MatrixTheme.getStatusStyle(_statusMessage),
                            textAlign: TextAlign.center,
                          ),
                        ),

                      // Login Button
                      SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _login,
                          style: MatrixTheme.primaryButtonStyle,
                          child:
                              _isLoading
                                  ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        context.colors.onSurface,
                                      ),
                                      strokeWidth: 2,
                                    ),
                                  )
                                  : const Text(
                                    'LOGIN',
                                    style: MatrixTheme.buttonStyle,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

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

  Widget _buildMatrixTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    String? Function(String?)? validator,
  }) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: MatrixTheme.labelStyle.copyWith(
                color: MatrixTheme.getTextColor(themeProvider.isDarkMode),
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: controller,
              obscureText: isPassword && !_showPassword,
              style: MatrixTheme.inputStyle.copyWith(
                color: MatrixTheme.getTextColor(themeProvider.isDarkMode),
              ),
              decoration: MatrixTheme.getInputDecoration(
                hintText: hint,
                prefixIcon: icon,
                suffixIcon:
                    isPassword
                        ? (_showPassword
                            ? Icons.visibility_off
                            : Icons.visibility)
                        : null,
                onSuffixPressed:
                    isPassword
                        ? () {
                          setState(() {
                            _showPassword = !_showPassword;
                          });
                        }
                        : null,
                isDarkMode: themeProvider.isDarkMode,
              ),
              validator: validator,
            ),
          ],
        );
      },
    );
  }
}
