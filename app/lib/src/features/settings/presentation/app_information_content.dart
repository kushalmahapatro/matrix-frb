/// Markdown copy for in-app FAQ and credits (settings → App information).
class AppInformationContent {
  AppInformationContent._();

  static const String faqMarkdown = '''
## Push notifications

This app registers with your homeserver when Matrix push is configured at build time. If notifications do not arrive, open **Settings → Notifications** to re-register, and confirm the homeserver allows push for your account.

## Encryption and key backup

End-to-end encryption uses keys stored on this device. If you use **key backup**, keep your recovery passphrase or security key somewhere safe — the app cannot reset it for you. Use **Set up key backup** or **Unlock with passphrase** under Encryption when prompted.

## Calls and media

Voice and video depend on OS permissions (microphone, camera) and network quality. If something fails, try again after granting permissions in system settings.

## Still stuck?

Use **Share app logs** from Settings to send a compressed copy of diagnostic logs (no message contents are added by that export — only what the logging layer already writes).
''';

  static const String creditsMarkdown = '''
## Matrix Terminal

Built with [Flutter](https://flutter.dev), the [Matrix Rust SDK](https://github.com/matrix-org/matrix-rust-sdk), and the open Matrix ecosystem.

## Thanks

To the Matrix.org Foundation and everyone who contributes to Matrix clients, servers, and specifications.

---
*Matrix is a trademark of The Matrix.org Foundation Ltd.*
''';
}
