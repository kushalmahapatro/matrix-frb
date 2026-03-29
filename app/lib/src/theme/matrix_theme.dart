import 'package:flutter/material.dart';
import 'package:matrix/src/core/logging_service.dart';
import 'package:matrix/src/theme/theme_provider.dart';
import 'package:provider/provider.dart';

class MatrixTheme {
  static bool _isDarkMode = true;
  // ignore: unused_element
  static void updateThemeMode(bool isDarkMode) {
    // _isDarkMode = isDarkMode;
  }

  // Font family
  static const String fontFamily = 'JetBrainsMono';

  // Matrix movie colors — phosphor-bright (avoid muddy / grayed secondary greens)
  static const Color matrixGreen = Color(0xFF00FF41);
  static const Color matrixDarkGreen = Color(0xFF00C938);
  static const Color matrixLightGreen = Color(0xFF8FFF9A);
  static const Color matrixAccent = Color(0xFF00FFD0);

  // Terminal colors — green-tinted blacks (less flat than neutral #0D1117)
  static const Color terminalBlack = Color(0xFF000000);
  static const Color terminalDarkGreen = Color(0xFF001A0D);
  static const Color terminalBackground = Color(0xFF06140C);
  static const Color terminalBorder = Color(0xFF1F7A45);

  // Status colors
  static const Color errorRed = Color(0xFFFF4444);
  static const Color warningOrange = Color(0xFFFF8800);
  static const Color successGreen = Color(0xFF00FF41);

  // Legacy colors for compatibility
  static const Color primaryGreen = matrixGreen;
  static const Color darkGreen = matrixDarkGreen;
  static const Color lightGreen = matrixLightGreen;
  static const Color backgroundBlack = terminalBlack;
  static const Color darkBackground = terminalDarkGreen;
  static const Color backgroundWhite = Colors.white;
  static const Color lightBackground = Color.fromARGB(255, 255, 249, 249);

  // Terminal Text Styles
  static const TextStyle logoStyle = TextStyle(
    color: matrixGreen,
    fontSize: 48,
    fontWeight: FontWeight.bold,
    fontFamily: fontFamily,
    letterSpacing: 8,
    shadows: [
      Shadow(color: matrixGreen, blurRadius: 20),
      Shadow(color: matrixGreen, blurRadius: 40),
    ],
  );

  static const TextStyle titleStyle = TextStyle(
    color: matrixGreen,
    fontSize: 24,
    fontWeight: FontWeight.bold,
    fontFamily: fontFamily,
    letterSpacing: 2,
    shadows: [Shadow(color: matrixGreen, blurRadius: 10)],
  );

  static const TextStyle subtitleStyle = TextStyle(
    color: matrixLightGreen,
    fontSize: 16,
    fontFamily: fontFamily,
    letterSpacing: 2,
  );

  static const TextStyle bodyStyle = TextStyle(
    color: matrixGreen,
    fontSize: 14,
    fontFamily: fontFamily,
    height: 1.4,
  );

  static const TextStyle captionStyle = TextStyle(
    color: matrixDarkGreen,
    fontSize: 12,
    fontFamily: fontFamily,
    letterSpacing: 1,
  );

  static const TextStyle buttonStyle = TextStyle(
    color: terminalBlack,
    fontSize: 16,
    fontWeight: FontWeight.bold,
    fontFamily: fontFamily,
    letterSpacing: 2,
  );

  static const TextStyle inputStyle = TextStyle(
    color: matrixGreen,
    fontSize: 16,
    fontFamily: fontFamily,
    height: 1.2,
  );

  static const TextStyle labelStyle = TextStyle(
    color: matrixGreen,
    fontSize: 12,
    fontFamily: fontFamily,
    fontWeight: FontWeight.bold,
    letterSpacing: 1,
  );

  static const TextStyle hintStyle = TextStyle(
    color: matrixDarkGreen,
    fontSize: 16,
    fontFamily: fontFamily,
  );

  static const TextStyle statusStyle = TextStyle(
    color: matrixGreen,
    fontSize: 14,
    fontFamily: fontFamily,
  );

  static const TextStyle errorStyle = TextStyle(
    color: errorRed,
    fontSize: 14,
    fontFamily: fontFamily,
  );

  static const TextStyle warningStyle = TextStyle(
    color: warningOrange,
    fontSize: 14,
    fontFamily: fontFamily,
  );

  // Matrix rain text style
  static const TextStyle matrixRainStyle = TextStyle(
    color: matrixGreen,
    fontSize: 15.0,
    fontFamily: fontFamily,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  // Terminal prompt style
  static const TextStyle terminalPromptStyle = TextStyle(
    color: matrixAccent,
    fontSize: 14,
    fontFamily: fontFamily,
    fontWeight: FontWeight.bold,
  );

  // Message styles
  static const TextStyle messageStyle = TextStyle(
    color: matrixGreen,
    fontSize: 14,
    fontFamily: fontFamily,
    height: 1.3,
  );

  static const TextStyle messageAuthorStyle = TextStyle(
    color: matrixAccent,
    fontSize: 12,
    fontFamily: fontFamily,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle messageTimeStyle = TextStyle(
    color: matrixDarkGreen,
    fontSize: 10,
    fontFamily: fontFamily,
  );

  // Terminal Decorations
  static BoxDecoration terminalDecoration = BoxDecoration(
    border: Border.all(color: matrixGreen, width: 2),
    borderRadius: BorderRadius.circular(4),
    color: terminalBlack,
    boxShadow: [
      BoxShadow(
        color: matrixGreen.withValues(alpha: 0.42),
        blurRadius: 12,
        spreadRadius: 0,
      ),
      BoxShadow(
        color: matrixAccent.withValues(alpha: 0.2),
        blurRadius: 20,
      ),
    ],
  );

  static BoxDecoration containerDecoration = BoxDecoration(
    border: Border.all(color: matrixGreen, width: 1),
    borderRadius: BorderRadius.circular(4),
    color: terminalBackground,
    boxShadow: [
      BoxShadow(
        color: matrixGreen.withValues(alpha: 0.22),
        blurRadius: 8,
        spreadRadius: 0,
      ),
      BoxShadow(
        color: matrixAccent.withValues(alpha: 0.12),
        blurRadius: 14,
      ),
    ],
  );

  static BoxDecoration cardDecoration = BoxDecoration(
    border: Border.all(color: terminalBorder, width: 1),
    borderRadius: BorderRadius.circular(4),
    color: terminalBackground,
    boxShadow: [
      BoxShadow(
        color: matrixDarkGreen.withValues(alpha: 0.35),
        blurRadius: 6,
      ),
    ],
  );

  static BoxDecoration statusDecoration = BoxDecoration(
    border: Border.all(color: matrixGreen, width: 1),
    borderRadius: BorderRadius.circular(2),
    color: terminalBlack.withValues(alpha: 0.8),
  );

  static BoxDecoration messageDecoration = BoxDecoration(
    border: Border(left: BorderSide(color: matrixAccent, width: 3)),
    color: terminalBackground.withValues(alpha: 0.72),
  );

  // Input decoration
  static InputDecoration inputDecoration({
    required String hintText,
    required IconData prefixIcon,
    IconData? suffixIcon,
    VoidCallback? onSuffixPressed,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: hintStyle.copyWith(color: primaryGreen.withValues(alpha: 0.5)),
      prefixIcon: Icon(prefixIcon, color: primaryGreen),
      suffixIcon: suffixIcon != null
          ? IconButton(
              icon: Icon(suffixIcon, color: primaryGreen),
              onPressed: onSuffixPressed,
            )
          : null,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: primaryGreen, width: 2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: primaryGreen, width: 2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: primaryGreen, width: 3),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: errorRed, width: 2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: errorRed, width: 3),
      ),
      filled: true,
      fillColor: backgroundBlack.withValues(alpha: 0.3),
    );
  }

  // Button styles
  static ButtonStyle primaryButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: primaryGreen,
    foregroundColor: backgroundBlack,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    elevation: 0,
  );

  static ButtonStyle secondaryButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: backgroundBlack,
    foregroundColor: primaryGreen,
    side: const BorderSide(color: primaryGreen, width: 2),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    elevation: 0,
  );

  static get colors => getTheme(_isDarkMode).colorScheme;

  // App theme - all colors from theme for dark/light adaptation
  static ThemeData getTheme(
    bool isDarkMode, {
    bool useDesktopChrome = false,
  }) {
    final bg = getBackgroundColor(isDarkMode);
    final text = getTextColor(isDarkMode);
    final container = getContainerColor(isDarkMode);
    final colorScheme = isDarkMode
        ? ColorScheme.dark(
            primary: matrixGreen,
            onPrimary: terminalBlack,
            surface: terminalBlack,
            onSurface: matrixGreen,
            surfaceContainerHighest: terminalBackground,
            surfaceContainerLow: const Color(0xFF0A160F),
            error: errorRed,
            onError: terminalBlack,
            outline: matrixGreen,
            outlineVariant: const Color(0xFF1F3D2A),
          )
        : ColorScheme.light(
            primary: darkGreen,
            onPrimary: backgroundWhite,
            surface: backgroundWhite,
            onSurface: darkGreen,
            surfaceContainerHighest: lightBackground,
            error: errorRed,
            onError: backgroundWhite,
            outline: darkGreen,
            outlineVariant: darkGreen.withValues(alpha: 0.18),
          );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bg,
      fontFamily: fontFamily,
      brightness: isDarkMode ? Brightness.dark : Brightness.light,

      // App bar theme
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: text,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          fontFamily: fontFamily,
          letterSpacing: 2,
        ),
        iconTheme: IconThemeData(color: text),
        actionsIconTheme: IconThemeData(color: text),
      ),

      // Elevated button theme
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: getPrimaryButtonStyle(isDarkMode),
      ),

      // Floating action button theme
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: text,
        foregroundColor: bg,
      ),

      // Input decoration theme
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: text, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: text, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: text, width: 3),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: errorRed, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: errorRed, width: 3),
        ),
        filled: true,
        fillColor: container,
        hintStyle: hintStyle.copyWith(color: text.withValues(alpha: 0.5)),
        prefixIconColor: text,
        suffixIconColor: text,
      ),

      // Text theme
      textTheme: TextTheme(
        displayLarge: logoStyle.copyWith(color: text),
        displayMedium: titleStyle.copyWith(color: text),
        displaySmall: subtitleStyle.copyWith(color: text),
        bodyLarge: bodyStyle.copyWith(color: text),
        bodyMedium: bodyStyle.copyWith(color: text),
        bodySmall: captionStyle.copyWith(color: text),
        labelLarge: labelStyle.copyWith(color: text),
        labelMedium: labelStyle.copyWith(color: text),
        labelSmall: captionStyle.copyWith(color: text),
      ),

      // Icon theme
      iconTheme: IconThemeData(color: text),

      // Card theme
      cardTheme: CardThemeData(
        color: container,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: text, width: 1),
        ),
      ),

      // Divider theme
      dividerTheme: DividerThemeData(color: text.withValues(alpha: 0.45)),

      // Snackbar theme
      snackBarTheme: SnackBarThemeData(
        backgroundColor: text,
        contentTextStyle: bodyStyle.copyWith(color: bg),
      ),
    );

    if (!useDesktopChrome) return base;

    final scheme = base.colorScheme;
    return base.copyWith(
      visualDensity: VisualDensity.compact,
      scrollbarTheme: ScrollbarThemeData(
        thumbVisibility: WidgetStateProperty.all(true),
        thickness: WidgetStateProperty.all(7),
        radius: const Radius.circular(4),
        crossAxisMargin: 2,
        mainAxisMargin: 4,
        thumbColor: WidgetStateProperty.all(
          scheme.outline.withValues(alpha: 0.35),
        ),
      ),
      listTileTheme: ListTileThemeData(
        dense: true,
        visualDensity: VisualDensity.compact,
        minVerticalPadding: 2,
        horizontalTitleGap: 10,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          visualDensity: VisualDensity.compact,
          minimumSize: const Size(36, 36),
          padding: const EdgeInsets.all(6),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        labelTextStyle: WidgetStateProperty.resolveWith(
          (_) => base.textTheme.bodyMedium,
        ),
      ),
      appBarTheme: base.appBarTheme.copyWith(
        toolbarHeight: 40,
        centerTitle: false,
        titleSpacing: 16,
        titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(
          letterSpacing: 0.35,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.55),
        thickness: 1,
        space: 1,
      ),
    );
  }

  // Helper methods
  static TextStyle getStatusStyle(String message) {
    if (message.contains('SUCCESS')) {
      return statusStyle.copyWith(color: primaryGreen);
    } else if (message.contains('ERROR')) {
      return errorStyle;
    } else {
      return warningStyle;
    }
  }

  static Color getStatusColor(String message) {
    if (message.contains('SUCCESS')) {
      return primaryGreen;
    } else if (message.contains('ERROR')) {
      return errorRed;
    } else {
      return warningOrange;
    }
  }

  // Theme-specific methods
  static Color getBackgroundColor(bool isDarkMode) {
    return isDarkMode ? backgroundBlack : backgroundWhite;
  }

  static Color getSecondaryBackgroundColor(bool isDarkMode) {
    return isDarkMode ? darkBackground : lightBackground;
  }

  static Color getTextColor(bool isDarkMode) {
    return isDarkMode ? primaryGreen : darkGreen;
  }

  static Color getContainerColor(bool isDarkMode) {
    return isDarkMode
        ? backgroundBlack.withValues(alpha: 0.3)
        : backgroundWhite.withValues(alpha: 0.8);
  }

  static LinearGradient getBackgroundGradient(bool isDarkMode) {
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: isDarkMode
          ? [
              backgroundBlack,
              const Color(0xFF001208),
              darkBackground,
            ]
          : [backgroundWhite, lightBackground],
      stops: isDarkMode ? const [0.0, 0.45, 1.0] : null,
    );
  }

  static LinearGradient get backgroundGradient {
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: _isDarkMode
          ? [
              backgroundBlack,
              const Color(0xFF001208),
              darkBackground,
            ]
          : [backgroundWhite, lightBackground],
      stops: _isDarkMode ? const [0.0, 0.45, 1.0] : null,
    );
  }

  static BoxDecoration getContainerDecoration(bool isDarkMode) {
    return BoxDecoration(
      border: Border.all(color: getTextColor(isDarkMode), width: 2),
      borderRadius: BorderRadius.circular(8),
      color: getContainerColor(isDarkMode),
    );
  }

  static BoxDecoration getCardDecoration(bool isDarkMode) {
    return BoxDecoration(
      border: Border.all(color: getTextColor(isDarkMode), width: 1),
      borderRadius: BorderRadius.circular(8),
      color: getContainerColor(isDarkMode),
    );
  }

  static InputDecoration getInputDecoration({
    required String hintText,
    required IconData prefixIcon,
    IconData? suffixIcon,
    VoidCallback? onSuffixPressed,
    required bool isDarkMode,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: hintStyle.copyWith(
        color: getTextColor(isDarkMode).withValues(alpha: 0.5),
      ),
      prefixIcon: Icon(prefixIcon, color: getTextColor(isDarkMode)),
      suffixIcon: suffixIcon != null
          ? IconButton(
              icon: Icon(suffixIcon, color: getTextColor(isDarkMode)),
              onPressed: onSuffixPressed,
            )
          : null,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: getTextColor(isDarkMode), width: 2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: getTextColor(isDarkMode), width: 2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: getTextColor(isDarkMode), width: 3),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: errorRed, width: 2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: errorRed, width: 3),
      ),
      filled: true,
      fillColor: getContainerColor(isDarkMode),
    );
  }

  static ButtonStyle getPrimaryButtonStyle(bool isDarkMode) {
    return ElevatedButton.styleFrom(
      backgroundColor: getTextColor(isDarkMode),
      foregroundColor: getBackgroundColor(isDarkMode),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      elevation: 0,
    );
  }

  static ButtonStyle getSecondaryButtonStyle(bool isDarkMode) {
    return ElevatedButton.styleFrom(
      backgroundColor: getBackgroundColor(isDarkMode),
      foregroundColor: getTextColor(isDarkMode),
      side: BorderSide(color: getTextColor(isDarkMode), width: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      elevation: 0,
    );
  }

  static void updatePlatformBrightness(BuildContext context) {
    if (context.mounted) {
      // This method is called when the platform brightness changes (e.g., user switches to dark/light mode)
      final Brightness brightness = View.of(
        context,
      ).platformDispatcher.platformBrightness;
      // You can then update your app's theme based on this brightness
      // For example, using a state management solution or calling setState
      LoggingService.info(
        'MatrixTheme',
        'Platform brightness changed to: $brightness',
      );
      context.read<ThemeProvider>().setThemeMode(
        brightness == Brightness.dark
            ? MatrixThemeMode.dark
            : MatrixThemeMode.light,
      );
    }
  }
}
