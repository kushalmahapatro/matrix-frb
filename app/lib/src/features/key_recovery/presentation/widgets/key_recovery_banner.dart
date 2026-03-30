import 'package:flutter/material.dart';
import 'package:matrix/src/features/key_recovery/presentation/key_recovery_copy.dart';

/// Session-dismissible banner prompting the user to enable recovery or unlock.
///
/// If the user checks [KeyRecoveryCopy.bannerDontShowAgainLabel] and taps dismiss
/// or the primary action, [onDismiss]/[onSetUp] receive `true` so the host can
/// persist and hide the banner on future launches.
class KeyRecoveryBanner extends StatefulWidget {
  const KeyRecoveryBanner({
    super.key,
    required this.onSetUp,
    required this.onDismiss,
    this.preferUnlockFlow = false,
  });

  /// Called with whether “Don’t show again” is checked (persist when true).
  final void Function(bool dontShowAgain) onSetUp;

  final void Function(bool dontShowAgain) onDismiss;

  /// When true, a server-side backup likely exists — steer copy toward unlock, not new backup.
  final bool preferUnlockFlow;

  @override
  State<KeyRecoveryBanner> createState() => _KeyRecoveryBannerState();
}

class _KeyRecoveryBannerState extends State<KeyRecoveryBanner> {
  bool _dontShowAgain = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = widget.preferUnlockFlow
        ? KeyRecoveryCopy.bannerUnlockTitle
        : KeyRecoveryCopy.title;
    final body = widget.preferUnlockFlow
        ? KeyRecoveryCopy.bannerUnlockBody
        : KeyRecoveryCopy.educationParagraphs.first;
    final primaryLabel = widget.preferUnlockFlow ? 'UNLOCK' : 'CONTINUE';
    return Material(
      color: scheme.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 4, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.key_rounded, color: scheme.primary, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                            onTap: () => widget.onSetUp(_dontShowAgain),
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    body,
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Tap here to continue',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: scheme.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              FilledButton.tonal(
                                onPressed: () =>
                                    widget.onSetUp(_dontShowAgain),
                                child: Text(primaryLabel),
                              ),
                              TextButton(
                                onPressed: () =>
                                    widget.onDismiss(_dontShowAgain),
                                child: const Text('DISMISS'),
                              ),
                            ],
                          ),
                          CheckboxTheme(
                            data: CheckboxThemeData(
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              side: BorderSide(
                                color: scheme.outline.withValues(alpha: 0.8),
                              ),
                            ),
                            child: CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                KeyRecoveryCopy.bannerDontShowAgainLabel,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              value: _dontShowAgain,
                              onChanged: (v) {
                                setState(() => _dontShowAgain = v ?? false);
                              },
                              controlAffinity:
                                  ListTileControlAffinity.leading,
                              dense: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              tooltip: 'Dismiss',
              onPressed: () => widget.onDismiss(_dontShowAgain),
            ),
          ],
        ),
      ),
    );
  }
}
