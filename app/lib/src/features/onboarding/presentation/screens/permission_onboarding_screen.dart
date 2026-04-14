import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:matrix/src/core/notifications/matrix_notifications_coordinator.dart';
import 'package:matrix/src/core/navigation/navigator_service.dart';
import 'package:matrix/src/core/permissions/ios_matrix_microphone_channel.dart';
import 'package:matrix/src/core/permissions/permission_onboarding_prefs.dart';
import 'package:matrix/src/core/permissions/permission_onboarding_status.dart';
import 'package:matrix/src/core/presentation/widgets/terminal_container.dart';
import 'package:matrix/src/features/chat_lisitng/presentation/screens/chat_listing_screen.dart';
import 'package:matrix/src/features/splash/domain/services/matrix_service.dart';
import 'package:permission_handler/permission_handler.dart';

/// Explains notifications, microphone, and camera; shows granted / denied / not asked.
class PermissionOnboardingScreen extends StatefulWidget {
  const PermissionOnboardingScreen({super.key});

  @override
  State<PermissionOnboardingScreen> createState() =>
      _PermissionOnboardingScreenState();
}

class _PermissionOnboardingScreenState extends State<PermissionOnboardingScreen>
    with WidgetsBindingObserver {
  OnboardingPermissionStatus? _notif;
  OnboardingPermissionStatus? _mic;
  OnboardingPermissionStatus? _cam;

  bool _busyNotifications = false;
  bool _busyMic = false;
  bool _busyCamera = false;
  bool _autoContinuing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_bootstrap());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshStatuses());
    }
  }

  Future<void> _bootstrap() async {
    unawaited(MatrixService().startMatrixNotificationsIfReady());
    await _refreshStatuses();
  }

  Future<void> _refreshStatuses() async {
    if (!mounted || kIsWeb) return;
    final n = await PermissionOnboardingStatuses.notification();
    final m = await PermissionOnboardingStatuses.microphone();
    final c = await PermissionOnboardingStatuses.camera();
    if (!mounted) return;
    setState(() {
      _notif = n;
      _mic = m;
      _cam = c;
    });
    if (n == OnboardingPermissionStatus.granted &&
        m == OnboardingPermissionStatus.granted &&
        c == OnboardingPermissionStatus.granted) {
      await _continueIfNeeded();
    }
  }

  Future<void> _continueIfNeeded() async {
    if (_autoContinuing || !mounted) return;
    _autoContinuing = true;
    await PermissionOnboardingPrefs.setCompleted();
    if (!mounted) return;
    unawaited(MatrixService().startMatrixNotificationsIfReady());
    NavigatorService.pushReplacement(context, const ChatListingScreen());
  }

  Future<void> _allowNotifications() async {
    if (_busyNotifications || kIsWeb) return;
    setState(() => _busyNotifications = true);
    try {
      await MatrixNotificationsCoordinator.instance
          .requestOsNotificationPermissions();
      await _refreshStatuses();
    } finally {
      if (mounted) setState(() => _busyNotifications = false);
    }
  }

  Future<void> _allowMicrophone() async {
    if (_busyMic || kIsWeb) return;
    setState(() => _busyMic = true);
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await iosRequestRecordPermission();
      } else {
        await Permission.microphone.request();
      }
      await _refreshStatuses();
    } finally {
      if (mounted) setState(() => _busyMic = false);
    }
  }

  Future<void> _allowCamera() async {
    if (_busyCamera || kIsWeb) return;
    setState(() => _busyCamera = true);
    try {
      await Permission.camera.request();
      await _refreshStatuses();
    } finally {
      if (mounted) setState(() => _busyCamera = false);
    }
  }

  Future<void> _continue() async {
    await PermissionOnboardingPrefs.setCompleted();
    if (!mounted) return;
    unawaited(MatrixService().startMatrixNotificationsIfReady());
    NavigatorService.pushReplacement(context, const ChatListingScreen());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TerminalScreen(
      title: 'PERMISSIONS',
      showAppBar: true,
      automaticallyImplyLeading: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Stay connected',
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Grant what you are comfortable with. You can change these later '
              'in system settings. Tap Continue to skip any permission you do '
              'not want to enable now — we will ask again when a feature needs it.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            if (!kIsWeb) ...[
              _PermissionCard(
                title: 'Notifications',
                description:
                    'Alerts you to new messages, invites, and incoming calls '
                    'when the app is in the background.',
                status: _notif,
                busy: _busyNotifications,
                onAllow: _allowNotifications,
              ),
              const SizedBox(height: 16),
              _PermissionCard(
                title: 'Microphone',
                description:
                    'Needed for voice messages and voice calls. Video calls '
                    'also use your microphone.',
                status: _mic,
                busy: _busyMic,
                onAllow: _allowMicrophone,
              ),
              const SizedBox(height: 16),
              _PermissionCard(
                title: 'Camera',
                description:
                    'Needed for video calls and for taking photos or video to '
                    'send in chat.',
                status: _cam,
                busy: _busyCamera,
                onAllow: _allowCamera,
              ),
            ] else
              Text(
                'Permission prompts are not used on web in this build.',
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _continue,
              child: const Text('CONTINUE TO MATRIX'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.title,
    required this.description,
    required this.status,
    required this.busy,
    required this.onAllow,
  });

  final String title;
  final String description;
  final OnboardingPermissionStatus? status;
  final bool busy;
  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final onSurface = theme.colorScheme.onSurface;

    final (statusLabel, statusColor) = switch (status) {
      null => ('CHECKING…', onSurface.withValues(alpha: 0.6)),
      OnboardingPermissionStatus.granted => ('ALLOWED', primary),
      OnboardingPermissionStatus.denied => ('NOT ALLOWED', theme.colorScheme.error),
      OnboardingPermissionStatus.notDetermined =>
        ('NOT ASKED YET', onSurface.withValues(alpha: 0.7)),
    };

    return TerminalContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: theme.textTheme.titleSmall?.copyWith(
              color: primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(description, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 10),
          Text(
            'STATUS: $statusLabel',
            style: theme.textTheme.labelLarge?.copyWith(
              color: statusColor,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (status != OnboardingPermissionStatus.granted)
                FilledButton(
                  onPressed: busy || status == null ? null : onAllow,
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          status == OnboardingPermissionStatus.denied
                              ? 'TRY AGAIN'
                              : 'ALLOW',
                        ),
                ),
              if (status == OnboardingPermissionStatus.denied)
                TextButton(
                  onPressed: busy ? null : () => openAppSettings(),
                  child: const Text('Open settings'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
