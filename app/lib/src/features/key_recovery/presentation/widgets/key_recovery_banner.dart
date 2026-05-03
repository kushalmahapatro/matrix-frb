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
    final subtitle = widget.preferUnlockFlow
        ? KeyRecoveryCopy.bannerUnlockShort
        : KeyRecoveryCopy.bannerBackupShort;
    final primaryLabel = widget.preferUnlockFlow ? 'UNLOCK' : 'CONTINUE';

    return Material(
      color: scheme.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.key_rounded, color: scheme.primary, size: 20),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          height: 1.25,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                          height: 1.3,
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.tonal(
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => widget.onSetUp(_dontShowAgain),
                        child: Text(primaryLabel),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => widget.onDismiss(_dontShowAgain),
                        child: const Text('DISMISS'),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: Checkbox(
                            value: _dontShowAgain,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            side: BorderSide(
                              color: scheme.outline.withValues(alpha: 0.8),
                            ),
                            onChanged: (v) {
                              setState(() => _dontShowAgain = v ?? false);
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Text(
                              KeyRecoveryCopy.bannerDontShowAgainLabel,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(fontSize: 11.5, height: 1.25),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Dismiss',
              onPressed: () => widget.onDismiss(_dontShowAgain),
            ),
          ],
        ),
      ),
    );
  }
}
