import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/src/core/navigation/navigator_service.dart';
import 'package:matrix/src/core/presentation/widgets/terminal_container.dart';
import 'package:matrix/src/features/key_recovery/data/key_recovery_repository.dart';
import 'package:matrix/src/features/key_recovery/domain/key_recovery_prefs.dart';
import 'package:matrix/src/features/key_recovery/presentation/key_recovery_copy.dart';
import 'package:matrix/src/features/key_recovery/presentation/screens/login_recovery_unlock_screen.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';

/// Create or update key backup with a new recovery passphrase.
class SetupKeyRecoveryScreen extends StatefulWidget {
  const SetupKeyRecoveryScreen({
    super.key,
    this.showEducation = true,
    this.showSkip = false,
    this.onSkip,
    /// When set (e.g. post-registration), called after the user dismisses the recovery key dialog.
    this.onEnabled,
  });

  final bool showEducation;
  final bool showSkip;
  final VoidCallback? onSkip;
  final VoidCallback? onEnabled;

  @override
  State<SetupKeyRecoveryScreen> createState() => _SetupKeyRecoveryScreenState();
}

class _SetupKeyRecoveryScreenState extends State<SetupKeyRecoveryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;
  /// Homeserver already has a backup; offer unlock flow instead of only an error.
  bool _serverBackupAlreadyExists = false;
  bool _showPass = false;
  bool _showConfirm = false;

  @override
  void dispose() {
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _serverBackupAlreadyExists = false;
    });
    final repo = KeyRecoveryRepository(MatrixService().client);
    try {
      await repo.refreshState();
      final key = await repo.enableWithPassphrase(_pass.text);
      await KeyRecoveryPrefs.clearSoftLockout();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Save your recovery key'),
          content: SingleChildScrollView(
            child: SelectableText(
              key,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: key));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied to clipboard')),
                );
              },
              child: const Text('COPY'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('DONE'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (widget.onEnabled != null) {
        widget.onEnabled!();
      } else {
        NavigatorService.pop(context);
      }
    } catch (e) {
      final msg = e.toString();
      final lower = msg.toLowerCase();
      final serverBackupExists = msg.contains('BackupExistsOnServer') ||
          lower.contains('backup already exists on the homeserver') ||
          lower.contains('backup exists on server');
      setState(() {
        _serverBackupAlreadyExists = serverBackupExists;
        _error = serverBackupExists
            ? KeyRecoveryCopy.backupExistsOnServerHint()
            : 'Could not enable backup: $msg';
        _busy = false;
      });
    }
  }

  void _goToUnlockScreen() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (ctx) => const LoginRecoveryUnlockScreen(closeWhenDone: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TerminalScreen(
      title: 'KEY BACKUP',
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.showEducation) ...[
                Text(
                  KeyRecoveryCopy.title,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                KeyRecoveryCopy.educationText(context),
              ],
              TerminalTextField(
                controller: _pass,
                label: 'RECOVERY PASSPHRASE',
                hint: 'Choose a strong passphrase',
                icon: Icons.lock_outline,
                isPassword: true,
                obscureText: !_showPass,
                suffixIcon: _showPass ? Icons.visibility_off : Icons.visibility,
                onSuffixPressed: () => setState(() => _showPass = !_showPass),
                validator: (v) {
                  if (v == null || v.length < 8) {
                    return 'Use at least 8 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TerminalTextField(
                controller: _confirm,
                label: 'CONFIRM PASSPHRASE',
                hint: 'Repeat passphrase',
                icon: Icons.lock_outline,
                isPassword: true,
                obscureText: !_showConfirm,
                suffixIcon:
                    _showConfirm ? Icons.visibility_off : Icons.visibility,
                onSuffixPressed: () =>
                    setState(() => _showConfirm = !_showConfirm),
                validator: (v) {
                  if (v != _pass.text) {
                    return 'Passphrases do not match';
                  }
                  return null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              if (_serverBackupAlreadyExists) ...[
                const SizedBox(height: 16),
                SizedBox(
                  height: 48,
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _goToUnlockScreen,
                    child: const Text('UNLOCK WITH PASSPHRASE'),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Use this if you already set up backup before. Your passphrase '
                  'downloads the keys for this device.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ] else ...[
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
                        : const Text('ENABLE BACKUP'),
                  ),
                ),
              ],
              if (widget.showSkip && widget.onSkip != null) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _busy ? null : widget.onSkip,
                  child: const Text('SKIP FOR NOW'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
