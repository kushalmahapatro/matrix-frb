import 'package:flutter/material.dart';

/// Opens full-screen flows (create chat, settings, room info): desktop dialog
/// when [preferDialogOverModalSheet], otherwise [Navigator.push].
abstract class DesktopShellLauncher {
  Future<T?> openShellFlow<T extends Object?>({
    required BuildContext anchorContext,
    required Widget page,
    String? windowTitle,
    Size preferredWindowSize = const Size(520, 720),
  });
}

class DesktopShellScope extends InheritedWidget {
  const DesktopShellScope({
    super.key,
    required this.launcher,
    required super.child,
  });

  final DesktopShellLauncher launcher;

  static DesktopShellLauncher? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<DesktopShellScope>()?.launcher;
  }

  @override
  bool updateShouldNotify(covariant DesktopShellScope oldWidget) =>
      oldWidget.launcher != launcher;
}
