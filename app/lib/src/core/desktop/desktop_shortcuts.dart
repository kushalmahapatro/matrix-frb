import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Intents — handled by [MessagingDesktopShortcuts] / workspace WM.

class NewChatIntent extends Intent {
  const NewChatIntent();
}

class OpenSettingsIntent extends Intent {
  const OpenSettingsIntent();
}

class CloseOrClearIntent extends Intent {
  const CloseOrClearIntent();
}

/// Desktop (and keyboard hardware) shortcuts around the messaging shell.
class MessagingDesktopShortcuts extends StatelessWidget {
  const MessagingDesktopShortcuts({
    super.key,
    required this.child,
    required this.onNewChat,
    required this.onOpenSettings,
    required this.onCloseOrClear,
  });

  final Widget child;
  final VoidCallback onNewChat;
  final VoidCallback onOpenSettings;
  final VoidCallback onCloseOrClear;

  static final bool _isApple = defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        SingleActivator(
          LogicalKeyboardKey.keyN,
          meta: _isApple,
          control: !_isApple,
        ): const NewChatIntent(),
        SingleActivator(
          LogicalKeyboardKey.comma,
          meta: _isApple,
          control: !_isApple,
        ): const OpenSettingsIntent(),
        const SingleActivator(LogicalKeyboardKey.escape):
            const CloseOrClearIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          NewChatIntent: CallbackAction<NewChatIntent>(
            onInvoke: (_) {
              onNewChat();
              return null;
            },
          ),
          OpenSettingsIntent: CallbackAction<OpenSettingsIntent>(
            onInvoke: (_) {
              onOpenSettings();
              return null;
            },
          ),
          CloseOrClearIntent: CallbackAction<CloseOrClearIntent>(
            onInvoke: (_) {
              onCloseOrClear();
              return null;
            },
          ),
        },
        child: FocusTraversalGroup(policy: OrderedTraversalPolicy(), child: child),
      ),
    );
  }

  static String get _mod => _isApple ? '⌘' : 'Ctrl';

  /// Reference for menu bar **Help → Keyboard Shortcuts…** (macOS menu integration).
  static List<({String action, String shortcut})> messagingShortcutRows() {
    return [
      (action: 'New room', shortcut: '$_mod+N'),
      (action: 'Settings', shortcut: '$_mod+,'),
      (action: 'Close sheet, go back, or clear room (split)', shortcut: 'Esc'),
    ];
  }

  static Future<void> showShortcutsReferenceDialog(BuildContext context) {
    final rows = messagingShortcutRows();
    return showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Keyboard shortcuts'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Table(
                columnWidths: const {
                  0: FlexColumnWidth(2.2),
                  1: FlexColumnWidth(1),
                },
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  for (final r in rows)
                    TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                            top: 10,
                            bottom: 10,
                            right: 16,
                          ),
                          child: Text(r.action),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Text(
                            r.shortcut,
                            style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
}
