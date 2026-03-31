import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/src/core/desktop/desktop_ui_helpers.dart';
import 'package:matrix/src/core/layout/conversation_message_style_preference.dart';
import 'package:matrix/src/core/layout/messaging_layout_preference.dart';
import 'package:matrix/src/core/navigation/navigator_service.dart';
import 'package:provider/provider.dart';
import 'package:matrix/src/core/presentation/widgets/terminal_container.dart';
import 'package:matrix/src/features/settings/domain/profile_prefs.dart';
import 'package:matrix/src/features/key_recovery/domain/key_recovery_prefs.dart';
import 'package:matrix/src/features/key_recovery/presentation/key_recovery_copy.dart';
import 'package:matrix/src/features/key_recovery/presentation/screens/login_recovery_unlock_screen.dart';
import 'package:matrix/src/features/key_recovery/presentation/screens/setup_key_recovery_screen.dart';
import 'package:matrix/src/features/settings/presentation/screens/profile_screen.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';

Widget _settingsListTile({
  required BuildContext context,
  required IconData icon,
  required String title,
  required String subtitle,
  required VoidCallback onTap,
}) {
  final theme = Theme.of(context);
  return InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.primary, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            color: theme.colorScheme.primary,
            size: 20,
          ),
        ],
      ),
    ),
  );
}

/// Shown only while key backup / recovery is not in the `enabled` state.
class _EncryptionKeyBackupSection extends StatefulWidget {
  const _EncryptionKeyBackupSection();

  @override
  State<_EncryptionKeyBackupSection> createState() =>
      _EncryptionKeyBackupSectionState();
}

class _EncryptionKeyBackupSectionState extends State<_EncryptionKeyBackupSection> {
  bool? _backupEnabled;

  @override
  void initState() {
    super.initState();
    unawaited(_reloadRecoveryState());
  }

  Future<void> _reloadRecoveryState() async {
    try {
      await MatrixService().client.refreshRecoveryState();
      final s = await MatrixService().client.getRecoveryState();
      if (!mounted) return;
      setState(() => _backupEnabled = s == 'enabled');
    } catch (_) {
      if (!mounted) return;
      setState(() => _backupEnabled = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_backupEnabled == true) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        TerminalContainer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ENCRYPTION & KEY BACKUP',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Same as the reminder on the home screen. If the app says a backup '
                'already exists on your account, you did not lose it — it usually '
                'means another Matrix client or device created it. Use Unlock with '
                'passphrase and the passphrase or security key you saved then.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                KeyRecoveryCopy.passphraseChangeFaq,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              _settingsListTile(
                context: context,
                icon: Icons.key,
                title: 'Set up key backup',
                subtitle: 'Choose a passphrase and back up your keys',
                onTap: () async {
                  await NavigatorService.push(
                    context,
                    const SetupKeyRecoveryScreen(showEducation: true),
                  );
                  await _reloadRecoveryState();
                },
              ),
              _settingsListTile(
                context: context,
                icon: Icons.vpn_key_outlined,
                title: 'Unlock with passphrase',
                subtitle: 'Enter the recovery passphrase from another device',
                onTap: () async {
                  await NavigatorService.push(
                    context,
                    const LoginRecoveryUnlockScreen(closeWhenDone: true),
                  );
                  await _reloadRecoveryState();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TerminalScreen(
      title: 'SETTINGS',
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              TerminalContainer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ACCOUNT', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 16),
                    _settingsListTile(
                      context: context,
                      icon: Icons.person,
                      title: 'Profile',
                      subtitle: 'Manage your profile information',
                      onTap: () => NavigatorService.push(context, const ProfileScreen()),
                    ),
                    _settingsListTile(
                      context: context,
                      icon: Icons.logout,
                      title: 'Logout',
                      subtitle: 'Sign out of your account',
                      onTap: () => _showLogoutDialog(context),
                    ),
                  ],
                ),
              ),
              const _EncryptionKeyBackupSection(),
              const SizedBox(height: 16),
              Consumer<MessagingLayoutPreferenceNotifier>(
                builder: (context, layoutNotifier, _) {
                  return TerminalContainer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ROOM LIST & WORKSPACE',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Whether the room list sits beside the open chat or you navigate between full screens.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        RadioListTile<MessagingLayoutPreference>(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Automatic'),
                          subtitle: const Text(
                            'Desktop and wide portrait phone: room list beside the chat. '
                            'Narrow width, landscape phone, and tablet: stacked navigation.',
                          ),
                          value: MessagingLayoutPreference.auto,
                          groupValue: layoutNotifier.value,
                          onChanged: (v) {
                            if (v != null) unawaited(layoutNotifier.set(v));
                          },
                        ),
                        RadioListTile<MessagingLayoutPreference>(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('List + chat (columns)'),
                          subtitle: const Text(
                            'Keep the list and the selected room visible together when there is enough width.',
                          ),
                          value: MessagingLayoutPreference.split,
                          groupValue: layoutNotifier.value,
                          onChanged: (v) {
                            if (v != null) unawaited(layoutNotifier.set(v));
                          },
                        ),
                        RadioListTile<MessagingLayoutPreference>(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Stacked navigation'),
                          subtitle: const Text(
                            'One full screen at a time — list, then room, then back.',
                          ),
                          value: MessagingLayoutPreference.threaded,
                          groupValue: layoutNotifier.value,
                          onChanged: (v) {
                            if (v != null) unawaited(layoutNotifier.set(v));
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              Consumer<ConversationMessageStyleNotifier>(
                builder: (context, messageStyleNotifier, _) {
                  return TerminalContainer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MESSAGES IN CHAT',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'How incoming and outgoing bubbles are placed in the timeline.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        RadioListTile<ConversationMessageStyle>(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Automatic'),
                          subtitle: const Text(
                            'Same as classic chat: yours on one side, others on the other.',
                          ),
                          value: ConversationMessageStyle.auto,
                          groupValue: messageStyleNotifier.value,
                          onChanged: (v) {
                            if (v != null) unawaited(messageStyleNotifier.set(v));
                          },
                        ),
                        RadioListTile<ConversationMessageStyle>(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Threaded'),
                          subtitle: const Text(
                            'All messages align from the start; colors, names, and state still show who sent what.',
                          ),
                          value: ConversationMessageStyle.threaded,
                          groupValue: messageStyleNotifier.value,
                          onChanged: (v) {
                            if (v != null) unawaited(messageStyleNotifier.set(v));
                          },
                        ),
                        RadioListTile<ConversationMessageStyle>(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Left & right (classic chat)'),
                          subtitle: const Text(
                            'Outgoing and incoming on opposite sides.',
                          ),
                          value: ConversationMessageStyle.leftRight,
                          groupValue: messageStyleNotifier.value,
                          onChanged: (v) {
                            if (v != null) unawaited(messageStyleNotifier.set(v));
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              TerminalContainer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('PREFERENCES', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 16),
                    _settingsListTile(
                      context: context,
                      icon: Icons.notifications,
                      title: 'Notifications',
                      subtitle: 'Configure notification settings',
                      onTap: () {},
                    ),
                    _settingsListTile(
                      context: context,
                      icon: Icons.palette,
                      title: 'Theme',
                      subtitle: 'Matrix terminal theme (active)',
                      onTap: () {},
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (isDesktopTargetPlatform()) ...[
                TerminalContainer(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('KEYBOARD', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 12),
                      _shortcutRow(
                        theme,
                        'New chat / create room',
                        '⌘ N  /  Ctrl+N',
                      ),
                      _shortcutRow(
                        theme,
                        'Open settings',
                        '⌘ ,  /  Ctrl+,',
                      ),
                      _shortcutRow(
                        theme,
                        'Close conversation or clear selection',
                        'Esc',
                      ),
                      _shortcutRow(
                        theme,
                        'Send message (composer focused)',
                        'Enter  (Shift+Enter for newline)',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Messaging shortcuts apply on macOS, Windows, and Linux.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              TerminalContainer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ABOUT', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 16),
                    _settingsListTile(
                      context: context,
                      icon: Icons.info,
                      title: 'Version',
                      subtitle: 'Matrix Terminal v1.0.0',
                      onTap: () {},
                    ),
                    _settingsListTile(
                      context: context,
                      icon: Icons.code,
                      title: 'Source Code',
                      subtitle: 'View on GitHub',
                      onTap: () {},
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shortcutRow(ThemeData theme, String action, String keys) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Text(
              action,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              keys,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'JetBrainsMono',
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        title: Text('LOGOUT', style: theme.textTheme.titleLarge),
        content: Text(
          'Are you sure you want to logout?',
          style: theme.textTheme.bodyMedium,
        ),
        actions: [
          TerminalButton(
            text: 'CANCEL',
            onPressed: () => Navigator.of(context).pop(),
            isPrimary: false,
          ),
          const SizedBox(width: 8),
          TerminalButton(
            text: 'LOGOUT',
            onPressed: () {
              Navigator.of(context).pop();
              ProfilePrefs.instance.clear();
              unawaited(KeyRecoveryPrefs.clearBannerDontShowAgain());
              Navigator.of(
                context,
              ).pushNamedAndRemoveUntil('/', (route) => false);
            },
          ),
        ],
      ),
    );
  }
}
