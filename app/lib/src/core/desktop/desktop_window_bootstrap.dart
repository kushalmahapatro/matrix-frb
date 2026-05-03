import 'package:flutter/material.dart';

/// Entry point wrapper kept for call sites; multi-window uses
/// [desktop_multi_window], not Flutter [RegularWindow].
void runDesktopWindowedAppIfEnabled(Widget app) {
  runApp(app);
}
