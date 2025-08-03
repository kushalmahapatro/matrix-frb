import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:matrix/src/theme/theme_provider.dart';
import 'package:matrix/src/theme/matrix_theme.dart';

class ThemeSwitcher extends StatelessWidget {
  const ThemeSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return PopupMenuButton<MatrixThemeMode>(
          icon: Icon(
            themeProvider.getThemeModeIcon(),
            color: MatrixTheme.getTextColor(themeProvider.isDarkMode),
          ),
          onSelected: (MatrixThemeMode mode) {
            themeProvider.setThemeMode(mode);
          },
          itemBuilder: (BuildContext context) => [
            PopupMenuItem<MatrixThemeMode>(
              value: MatrixThemeMode.system,
              child: Row(
                children: [
                  Icon(
                    Icons.brightness_auto,
                    color: MatrixTheme.getTextColor(themeProvider.isDarkMode),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'SYSTEM',
                    style: MatrixTheme.bodyStyle.copyWith(
                      color: MatrixTheme.getTextColor(themeProvider.isDarkMode),
                    ),
                  ),
                  if (themeProvider.themeMode == MatrixThemeMode.system)
                    const Spacer(),
                  if (themeProvider.themeMode == MatrixThemeMode.system)
                    Icon(
                      Icons.check,
                      color: MatrixTheme.getTextColor(themeProvider.isDarkMode),
                    ),
                ],
              ),
            ),
            PopupMenuItem<MatrixThemeMode>(
              value: MatrixThemeMode.light,
              child: Row(
                children: [
                  Icon(
                    Icons.light_mode,
                    color: MatrixTheme.getTextColor(themeProvider.isDarkMode),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'LIGHT',
                    style: MatrixTheme.bodyStyle.copyWith(
                      color: MatrixTheme.getTextColor(themeProvider.isDarkMode),
                    ),
                  ),
                  if (themeProvider.themeMode == MatrixThemeMode.light)
                    const Spacer(),
                  if (themeProvider.themeMode == MatrixThemeMode.light)
                    Icon(
                      Icons.check,
                      color: MatrixTheme.getTextColor(themeProvider.isDarkMode),
                    ),
                ],
              ),
            ),
            PopupMenuItem<MatrixThemeMode>(
              value: MatrixThemeMode.dark,
              child: Row(
                children: [
                  Icon(
                    Icons.dark_mode,
                    color: MatrixTheme.getTextColor(themeProvider.isDarkMode),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'DARK',
                    style: MatrixTheme.bodyStyle.copyWith(
                      color: MatrixTheme.getTextColor(themeProvider.isDarkMode),
                    ),
                  ),
                  if (themeProvider.themeMode == MatrixThemeMode.dark)
                    const Spacer(),
                  if (themeProvider.themeMode == MatrixThemeMode.dark)
                    Icon(
                      Icons.check,
                      color: MatrixTheme.getTextColor(themeProvider.isDarkMode),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
} 