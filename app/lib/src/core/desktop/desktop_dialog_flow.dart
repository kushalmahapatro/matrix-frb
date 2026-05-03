import 'package:flutter/material.dart';

import 'desktop_esc_scope.dart';

/// Hosts a [Navigator] that immediately pushes [page] so inner screens can
/// [Navigator.pop] with a result (single-route dialogs cannot pop).
class DesktopDialogFlowHost extends StatefulWidget {
  const DesktopDialogFlowHost({super.key, required this.page});

  final Widget page;

  @override
  State<DesktopDialogFlowHost> createState() => _DesktopDialogFlowHostState();
}

class _DesktopDialogFlowHostState extends State<DesktopDialogFlowHost> {
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pushFlow());
  }

  Future<void> _pushFlow() async {
    final nav = _navKey.currentState;
    if (!mounted || nav == null) return;
    final result = await nav.push<Object?>(
      MaterialPageRoute<Object?>(
        fullscreenDialog: true,
        builder: (_) => DesktopEscScope(child: widget.page),
      ),
    );
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: _navKey,
      onGenerateInitialRoutes: (_, __) => [
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(
            backgroundColor: Colors.transparent,
            body: SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}
