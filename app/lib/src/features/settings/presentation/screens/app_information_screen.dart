import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:matrix/src/core/diagnostics/app_log_export_actions.dart';
import 'package:matrix/src/core/navigation/navigator_service.dart';
import 'package:matrix/src/core/presentation/widgets/terminal_container.dart';
import 'package:matrix/src/features/settings/presentation/app_information_content.dart';
import 'package:matrix/src/features/settings/presentation/screens/markdown_info_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

const _matrixOrgUrl = 'https://matrix.org';

/// Version, FAQ entry points, credits, and log export.
class AppInformationScreen extends StatelessWidget {
  const AppInformationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TerminalScreen(
      title: 'APP INFORMATION',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TerminalContainer(
              child: FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return Text(
                      'Loading version…',
                      style: theme.textTheme.bodyMedium,
                    );
                  }
                  final p = snap.data!;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Matrix Terminal',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Version ${p.version} (build ${p.buildNumber})',
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (p.installerStore?.isNotEmpty ?? false) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Installer: ${p.installerStore}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            TerminalContainer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('HELP', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 12),
                  _linkRow(
                    context,
                    icon: Icons.quiz_outlined,
                    title: 'FAQs',
                    subtitle: 'Notifications, encryption, calls',
                    onTap: () => NavigatorService.push(
                      context,
                      const MarkdownInfoScreen(
                        title: 'FAQs',
                        bodyMarkdown: AppInformationContent.faqMarkdown,
                      ),
                    ),
                  ),
                  _linkRow(
                    context,
                    icon: Icons.favorite_outline,
                    title: 'Credits',
                    subtitle: 'Acknowledgements',
                    onTap: () => NavigatorService.push(
                      context,
                      const MarkdownInfoScreen(
                        title: 'Credits',
                        bodyMarkdown: AppInformationContent.creditsMarkdown,
                      ),
                    ),
                  ),
                  _linkRow(
                    context,
                    icon: Icons.public,
                    title: 'Matrix.org',
                    subtitle: 'About the Matrix ecosystem',
                    onTap: () async {
                      final uri = Uri.parse(_matrixOrgUrl);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                  ),
                ],
              ),
            ),
            if (!kIsWeb) ...[
              const SizedBox(height: 16),
              TerminalContainer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('DIAGNOSTICS', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      'Rust tracing logs are written to a rolling file under the app cache. '
                      'You can share a ZIP of that folder for support.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _linkRow(
                      context,
                      icon: Icons.ios_share_outlined,
                      title: 'Share app logs',
                      subtitle: 'Create a ZIP and open the system share sheet',
                      onTap: () => unawaited(
                        AppLogExportActions.shareLogs(context),
                      ),
                    ),
                    _linkRow(
                      context,
                      icon: Icons.save_alt_outlined,
                      title: 'Save log archive…',
                      subtitle: 'Pick a location and store the ZIP file',
                      onTap: () => unawaited(
                        AppLogExportActions.saveLogsToDisk(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static Widget _linkRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
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

}
