import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Dismisses the nearest [Navigator] route on Escape (desktop overlays).
///
/// Requests focus after the first frame so shortcuts are active even when no
/// inner widget (e.g. [TextField]) steals initial focus.
class DesktopEscScope extends StatefulWidget {
  const DesktopEscScope({super.key, required this.child});

  final Widget child;

  @override
  State<DesktopEscScope> createState() => _DesktopEscScopeState();
}

class _DesktopEscScopeState extends State<DesktopEscScope> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'desktopEscScope', skipTraversal: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () {
          final nav = Navigator.maybeOf(context);
          if (nav != null && nav.canPop()) {
            nav.pop();
          }
        },
      },
      child: Focus(
        focusNode: _focusNode,
        canRequestFocus: true,
        skipTraversal: true,
        child: widget.child,
      ),
    );
  }
}
