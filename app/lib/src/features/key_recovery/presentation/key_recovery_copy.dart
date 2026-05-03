import 'package:flutter/material.dart';

/// User-facing copy for key backup / recovery (secret storage + server backup).
class KeyRecoveryCopy {
  KeyRecoveryCopy._();

  static const title = 'Back up your encryption keys';

  /// Banner when a server backup exists but this session is not fully recovered.
  static const bannerUnlockTitle = 'Unlock encryption on this device';

  /// Home banner: persistently hide after the user takes an action with this checked.
  static const bannerDontShowAgainLabel = "Don't show again";

  static const bannerUnlockBody =
      'Your account already has an encrypted key backup on the server — often from '
      'another Matrix app or an older device. You do not need to create a new backup '
      'here. Enter the recovery passphrase or security key you saved when you first '
      'set up backup (you may not remember the exact moment; password managers and '
      'old device exports are good places to check).';

  /// Short line for the home banner; full detail is in the unlock / setup flow.
  static const bannerUnlockShort =
      'Use your saved recovery passphrase or security key to unlock this device.';

  /// Short line for the home backup banner (see [educationParagraphs] for full copy).
  static const bannerBackupShort =
      'Set up recovery to read encrypted history on new devices.';

  static const educationParagraphs = <String>[
    'Matrix encrypts your messages on this device. If you sign in on another phone '
        'or computer, or lose this device, you need a recovery secret to read your '
        'history and stay trusted across devices.',
    'Choose a strong passphrase you do not use elsewhere. It encrypts your backup on '
        'the server so only you can restore it.',
  ];

  static Widget educationText(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final p in educationParagraphs) ...[
          Text(p, style: style),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  static String backupExistsOnServerHint() {
    return 'A key backup already exists on your account. If this device cannot connect '
        'to it, open Matrix on a device where encryption already works, or enter your '
        'existing recovery passphrase on the unlock screen after login.';
  }

  /// Settings / help: rotating the recovery passphrase.
  static const passphraseChangeFaq =
      'You can only change your recovery passphrase if you still know the current one '
      '(or you have the security key). That proves you can decrypt the existing backup; '
      'then a client can create a new passphrase. This app does not yet include a '
      '"change passphrase" screen — use Element or another Matrix client to rotate '
      'recovery if you need to. If you have lost both passphrase and security key, '
      'you cannot recover old encrypted history; you can still use the app for new '
      'messages on this device.';
}
