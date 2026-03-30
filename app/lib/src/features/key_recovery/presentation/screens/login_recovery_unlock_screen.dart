import 'package:flutter/material.dart';
import 'package:matrix/src/core/navigation/navigator_service.dart';
import 'package:matrix/src/core/presentation/widgets/terminal_container.dart';
import 'package:matrix/src/features/chat_lisitng/presentation/screens/chat_listing_screen.dart';
import 'package:matrix/src/features/key_recovery/data/key_recovery_repository.dart';
import 'package:matrix/src/features/key_recovery/domain/key_recovery_prefs.dart';
import 'package:matrix/src/features/key_recovery/presentation/key_recovery_copy.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';

/// Blocking screen after login when account has secret storage but this device
/// has not imported keys yet.
///
/// When [closeWhenDone] is true (banner / settings), pops the current route on
/// success or after lockout. Otherwise replaces the stack with the chat listing
/// (post-login gate).
class LoginRecoveryUnlockScreen extends StatefulWidget {
  const LoginRecoveryUnlockScreen({
    super.key,
    this.closeWhenDone = false,
  });

  final bool closeWhenDone;

  @override
  State<LoginRecoveryUnlockScreen> createState() =>
      _LoginRecoveryUnlockScreenState();
}

class _LoginRecoveryUnlockScreenState extends State<LoginRecoveryUnlockScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passphrase = TextEditingController();
  bool _busy = false;
  int _failedAttempts = 0;
  bool _showPass = false;

  @override
  void dispose() {
    _passphrase.dispose();
    super.dispose();
  }

  void _finishAfterResult() {
    if (!mounted) return;
    if (widget.closeWhenDone) {
      NavigatorService.pop(context);
    } else {
      NavigatorService.pushReplacement(context, const ChatListingScreen());
    }
  }

  String _warningForAttempt() {
    if (_failedAttempts == 0) return '';
    if (_failedAttempts == 1) {
      return 'That passphrase did not work. Please check caps lock and try again. '
          'You have 2 attempts left before this device continues without restoring keys.';
    }
    return 'Incorrect again. One more failed attempt will skip recovery on this device. '
        'Older encrypted messages may not decrypt until you enter the correct passphrase '
        'from Settings.';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final repo = KeyRecoveryRepository(MatrixService().client);
    try {
      await repo.recoverWithPassphrase(_passphrase.text);
      await KeyRecoveryPrefs.clearSoftLockout();
      if (!mounted) return;
      _finishAfterResult();
    } catch (_) {
      final next = _failedAttempts + 1;
      if (next >= 3) {
        await KeyRecoveryPrefs.setSoftLockout(true);
        if (!mounted) return;
        _finishAfterResult();
        return;
      }
      setState(() {
        _failedAttempts = next;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TerminalScreen(
      title: 'UNLOCK ENCRYPTION',
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Your account has a key backup. Enter the recovery passphrase or '
                'security key you saved when you set up encryption.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              KeyRecoveryCopy.educationText(context),
              if (_warningForAttempt().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  _warningForAttempt(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              TerminalTextField(
                controller: _passphrase,
                label: 'RECOVERY PASSPHRASE OR KEY',
                hint: 'Enter passphrase or security key',
                icon: Icons.vpn_key_outlined,
                isPassword: true,
                obscureText: !_showPass,
                suffixIcon: _showPass ? Icons.visibility_off : Icons.visibility,
                onSuffixPressed: () => setState(() => _showPass = !_showPass),
                validator: (v) {
                  if (v == null || v.isEmpty) {
                    return 'Required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('UNLOCK'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
