import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:matrix/src/theme/matrix_theme.dart';

enum MatrixThemeMode { system, light, dark }

class ThemeProvider extends ChangeNotifier {
  static const String _themeKey = 'matrix_theme_mode';

  MatrixThemeMode _themeMode = MatrixThemeMode.system;
  bool _isDarkMode = false;

  MatrixThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _isDarkMode;

  // Get the current theme data
  ThemeData get theme => MatrixTheme.getTheme(_isDarkMode);

  // Get background gradient
  LinearGradient get backgroundGradient =>
      MatrixTheme.getBackgroundGradient(_isDarkMode);

  // Get text color
  Color get textColor => MatrixTheme.getTextColor(_isDarkMode);

  // Get background color
  Color get backgroundColor => MatrixTheme.getBackgroundColor(_isDarkMode);

  // Get container color
  Color get containerColor => MatrixTheme.getContainerColor(_isDarkMode);

  ThemeProvider() {
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt(_themeKey) ?? -1;
    if (themeIndex == -1) {
      _themeMode = MatrixThemeMode.system;
      setThemeMode(_themeMode);
    } else {
      _themeMode = MatrixThemeMode.values[themeIndex];
    }
    _updateThemeMode();
    notifyListeners();
  }

  Future<void> setThemeMode(MatrixThemeMode mode) async {
    if (_themeMode == mode) return;

    _themeMode = mode;
    _updateThemeMode();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, mode.index);

    notifyListeners();
  }

  void _updateThemeMode() {
    switch (_themeMode) {
      case MatrixThemeMode.system:
        final Brightness brightness =
            WidgetsBinding.instance.platformDispatcher.platformBrightness;
        _isDarkMode = brightness == Brightness.dark;
        break;
      case MatrixThemeMode.light:
        _isDarkMode = false;
        break;
      case MatrixThemeMode.dark:
        _isDarkMode = true;
        break;
    }
    MatrixTheme.updateThemeMode(_isDarkMode);
  }

  void updateSystemTheme(Brightness brightness) {
    if (_themeMode == MatrixThemeMode.system) {
      _isDarkMode = brightness == Brightness.dark;
      notifyListeners();
    }
  }

  String getThemeModeName() {
    switch (_themeMode) {
      case MatrixThemeMode.system:
        return 'SYSTEM';
      case MatrixThemeMode.light:
        return 'LIGHT';
      case MatrixThemeMode.dark:
        return 'DARK';
    }
  }

  IconData getThemeModeIcon() {
    switch (_themeMode) {
      case MatrixThemeMode.system:
        return Icons.brightness_auto;
      case MatrixThemeMode.light:
        return Icons.light_mode;
      case MatrixThemeMode.dark:
        return Icons.dark_mode;
    }
  }
}
