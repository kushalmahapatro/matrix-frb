import 'package:flutter/material.dart';
import 'package:matrix/src/core/navigation/navigator_service.dart';
import 'package:matrix/src/core/presentation/widgets/terminal_container.dart';
import 'package:matrix/src/features/settings/presentation/screens/profile_screen.dart';

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
                    _buildSettingItem(
                      context: context,
                      icon: Icons.person,
                      title: 'Profile',
                      subtitle: 'Manage your profile information',
                      onTap: () => NavigatorService.push(context, const ProfileScreen()),
                    ),
                    _buildSettingItem(
                      context: context,
                      icon: Icons.security,
                      title: 'Security',
                      subtitle: 'Manage security settings',
                      onTap: () {},
                    ),
                    _buildSettingItem(
                      context: context,
                      icon: Icons.logout,
                      title: 'Logout',
                      subtitle: 'Sign out of your account',
                      onTap: () => _showLogoutDialog(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TerminalContainer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('PREFERENCES', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 16),
                    _buildSettingItem(
                      context: context,
                      icon: Icons.notifications,
                      title: 'Notifications',
                      subtitle: 'Configure notification settings',
                      onTap: () {},
                    ),
                    _buildSettingItem(
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
              TerminalContainer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ABOUT', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 16),
                    _buildSettingItem(
                      context: context,
                      icon: Icons.info,
                      title: 'Version',
                      subtitle: 'Matrix Terminal v1.0.0',
                      onTap: () {},
                    ),
                    _buildSettingItem(
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

  Widget _buildSettingItem({
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
              // Implement logout logic
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
