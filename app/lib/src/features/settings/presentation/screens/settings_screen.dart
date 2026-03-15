import 'package:flutter/material.dart';
import 'package:matrix/src/core/presentation/widgets/terminal_container.dart';
import 'package:matrix/src/theme/matrix_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return TerminalScreen(
      title: "SETTINGS",
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TerminalContainer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ACCOUNT', style: MatrixTheme.titleStyle),
                  const SizedBox(height: 16),
                  _buildSettingItem(
                    icon: Icons.person,
                    title: 'Profile',
                    subtitle: 'Manage your profile information',
                    onTap: () {},
                  ),
                  _buildSettingItem(
                    icon: Icons.security,
                    title: 'Security',
                    subtitle: 'Manage security settings',
                    onTap: () {},
                  ),
                  _buildSettingItem(
                    icon: Icons.logout,
                    title: 'Logout',
                    subtitle: 'Sign out of your account',
                    onTap: () {
                      _showLogoutDialog(context);
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            TerminalContainer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('PREFERENCES', style: MatrixTheme.titleStyle),
                  const SizedBox(height: 16),
                  _buildSettingItem(
                    icon: Icons.notifications,
                    title: 'Notifications',
                    subtitle: 'Configure notification settings',
                    onTap: () {},
                  ),
                  _buildSettingItem(
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
                  const Text('ABOUT', style: MatrixTheme.titleStyle),
                  const SizedBox(height: 16),
                  _buildSettingItem(
                    icon: Icons.info,
                    title: 'Version',
                    subtitle: 'Matrix Terminal v1.0.0',
                    onTap: () {},
                  ),
                  _buildSettingItem(
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
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0),
        child: Row(
          children: [
            Icon(icon, color: MatrixTheme.matrixGreen, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: MatrixTheme.bodyStyle.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: MatrixTheme.captionStyle),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: MatrixTheme.matrixGreen,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: MatrixTheme.terminalBackground,
            title: const Text('LOGOUT', style: MatrixTheme.titleStyle),
            content: const Text(
              'Are you sure you want to logout?',
              style: MatrixTheme.bodyStyle,
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
