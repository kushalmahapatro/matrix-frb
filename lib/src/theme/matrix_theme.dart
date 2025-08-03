import 'package:flutter/material.dart';
import 'package:matrix/src/theme/theme_provider.dart';
import 'package:provider/provider.dart';

class MatrixTheme {
  // Font family
  static const String fontFamily = 'JetBrainsMono';

  // Colors
  static const Color primaryGreen = Color.fromARGB(255, 21, 126, 21);
  static const Color darkGreen = Color.fromARGB(255, 21, 126, 21);
  static const Color lightGreen = Color.fromARGB(255, 21, 126, 21);
  static const Color errorRed = Color(0xFFFF4444);
  static const Color warningOrange = Color(0xFFFF8800);

  // Dark theme colors
  static const Color backgroundBlack = Colors.black;
  static const Color darkBackground = Color(0xFF001100);

  // Light theme colors
  static const Color backgroundWhite = Colors.white;
  static const Color lightBackground = Color.fromARGB(255, 255, 249, 249);

  // Text Styles
  static const TextStyle logoStyle = TextStyle(
    color: primaryGreen,
    fontSize: 48,
    fontWeight: FontWeight.bold,
    fontFamily: fontFamily,
    letterSpacing: 8,
    shadows: [Shadow(color: primaryGreen, blurRadius: 20)],
  );

  static const TextStyle titleStyle = TextStyle(
    color: primaryGreen,
    fontSize: 24,
    fontWeight: FontWeight.bold,
    fontFamily: fontFamily,
    letterSpacing: 2,
  );

  static const TextStyle subtitleStyle = TextStyle(
    color: primaryGreen,
    fontSize: 16,
    fontFamily: fontFamily,
    letterSpacing: 2,
  );

  static const TextStyle bodyStyle = TextStyle(
    color: primaryGreen,
    fontSize: 14,
    fontFamily: fontFamily,
  );

  static const TextStyle captionStyle = TextStyle(
    color: primaryGreen,
    fontSize: 12,
    fontFamily: fontFamily,
    letterSpacing: 1,
  );

  static const TextStyle buttonStyle = TextStyle(
    color: backgroundBlack,
    fontSize: 16,
    fontWeight: FontWeight.bold,
    fontFamily: fontFamily,
    letterSpacing: 2,
  );

  static const TextStyle inputStyle = TextStyle(
    color: primaryGreen,
    fontSize: 16,
    fontFamily: fontFamily,
  );

  static const TextStyle labelStyle = TextStyle(
    color: primaryGreen,
    fontSize: 12,
    fontFamily: fontFamily,
    fontWeight: FontWeight.bold,
    letterSpacing: 1,
  );

  static const TextStyle hintStyle = TextStyle(
    color: primaryGreen,
    fontSize: 16,
    fontFamily: fontFamily,
  );

  static const TextStyle statusStyle = TextStyle(
    color: primaryGreen,
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
    color: primaryGreen,
    fontSize: 15.0,
    fontFamily: fontFamily,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  // Decorations
  static BoxDecoration containerDecoration = BoxDecoration(
    border: Border.all(color: primaryGreen, width: 2),
    borderRadius: BorderRadius.circular(8),
    color: backgroundBlack.withValues(alpha: 0.3),
  );

  static BoxDecoration cardDecoration = BoxDecoration(
    border: Border.all(color: primaryGreen, width: 1),
    borderRadius: BorderRadius.circular(8),
    color: backgroundBlack.withValues(alpha: 0.3),
  );

  static BoxDecoration statusDecoration = BoxDecoration(
    border: Border.all(color: primaryGreen, width: 1),
    borderRadius: BorderRadius.circular(4),
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
      suffixIcon:
          suffixIcon != null
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

  // App theme
  static ThemeData getTheme(bool isDarkMode) {
    return ThemeData(
      primarySwatch: Colors.green,
      useMaterial3: true,
      scaffoldBackgroundColor: getBackgroundColor(isDarkMode),
      fontFamily: fontFamily,
      brightness: isDarkMode ? Brightness.dark : Brightness.light,

      // App bar theme
      appBarTheme: AppBarTheme(
        backgroundColor: getBackgroundColor(isDarkMode),
        foregroundColor: getTextColor(isDarkMode),
        elevation: 0,
        titleTextStyle: TextStyle(
          color: getTextColor(isDarkMode),
          fontSize: 20,
          fontWeight: FontWeight.bold,
          fontFamily: fontFamily,
          letterSpacing: 2,
        ),
        iconTheme: IconThemeData(color: getTextColor(isDarkMode)),
        actionsIconTheme: IconThemeData(color: getTextColor(isDarkMode)),
      ),

      // Elevated button theme
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: getPrimaryButtonStyle(isDarkMode),
      ),

      // Floating action button theme
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: getTextColor(isDarkMode),
        foregroundColor: getBackgroundColor(isDarkMode),
      ),

      // Input decoration theme
      inputDecorationTheme: InputDecorationTheme(
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
        hintStyle: hintStyle.copyWith(
          color: getTextColor(isDarkMode).withValues(alpha: 0.5),
        ),
        prefixIconColor: getTextColor(isDarkMode),
        suffixIconColor: getTextColor(isDarkMode),
      ),

      // Text theme
      textTheme: TextTheme(
        displayLarge: logoStyle.copyWith(color: getTextColor(isDarkMode)),
        displayMedium: titleStyle.copyWith(color: getTextColor(isDarkMode)),
        displaySmall: subtitleStyle.copyWith(color: getTextColor(isDarkMode)),
        bodyLarge: bodyStyle.copyWith(color: getTextColor(isDarkMode)),
        bodyMedium: bodyStyle.copyWith(color: getTextColor(isDarkMode)),
        bodySmall: captionStyle.copyWith(color: getTextColor(isDarkMode)),
        labelLarge: labelStyle.copyWith(color: getTextColor(isDarkMode)),
        labelMedium: labelStyle.copyWith(color: getTextColor(isDarkMode)),
        labelSmall: captionStyle.copyWith(color: getTextColor(isDarkMode)),
      ),

      // Icon theme
      iconTheme: IconThemeData(color: getTextColor(isDarkMode)),

      // Card theme
      cardTheme: CardTheme(
        color: getContainerColor(isDarkMode),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: getTextColor(isDarkMode), width: 1),
        ),
      ),

      // Divider theme
      dividerTheme: DividerThemeData(
        color: getTextColor(isDarkMode).withValues(alpha: 0.3),
      ),

      // Snackbar theme
      snackBarTheme: SnackBarThemeData(
        backgroundColor: getTextColor(isDarkMode),
        contentTextStyle: bodyStyle.copyWith(
          color: getBackgroundColor(isDarkMode),
        ),
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
      colors:
          isDarkMode
              ? [backgroundBlack, darkBackground]
              : [backgroundWhite, lightBackground],
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
      suffixIcon:
          suffixIcon != null
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
      final Brightness brightness =
          View.of(context).platformDispatcher.platformBrightness;
      // You can then update your app's theme based on this brightness
      // For example, using a state management solution or calling setState
      print('Platform brightness changed to: $brightness');
      context.read<ThemeProvider>().setThemeMode(
        brightness == Brightness.dark
            ? MatrixThemeMode.dark
            : MatrixThemeMode.light,
      );
    }
  }
}
