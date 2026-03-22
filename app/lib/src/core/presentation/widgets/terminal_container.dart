import 'package:flutter/material.dart';
import 'package:matrix/src/theme/matrix_theme.dart';

class TerminalContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final bool showBorder;
  final bool showGlow;
  final Color? borderColor;
  /// Panel fill; defaults to [ColorScheme.surfaceContainerHighest].
  final Color? backgroundColor;
  final double? width;
  final double? height;

  const TerminalContainer({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.showBorder = true,
    this.showGlow = false,
    this.borderColor,
    this.backgroundColor,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = borderColor ?? theme.colorScheme.primary;
    return Container(
      width: width,
      height: height,
      margin: margin,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: showBorder ? Border.all(color: border, width: 1) : null,
        borderRadius: BorderRadius.circular(4),
        color: backgroundColor ?? theme.colorScheme.surfaceContainerHighest,
        boxShadow: showGlow
            ? [
                BoxShadow(
                  color: border.withValues(alpha: 0.48),
                  blurRadius: 14,
                  spreadRadius: 0,
                ),
                BoxShadow(
                  color: MatrixTheme.matrixAccent.withValues(alpha: 0.18),
                  blurRadius: 18,
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}

class TerminalScreen extends StatelessWidget {
  final Widget child;
  final String? title;
  final List<Widget>? actions;
  final bool showAppBar;

  const TerminalScreen({
    super.key,
    required this.child,
    this.title,
    this.actions,
    this.showAppBar = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final barTitle = Text(
      title ?? '',
      style: MatrixTheme.subtitleStyle.copyWith(
        color: MatrixTheme.matrixLightGreen,
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: 3,
        shadows: [
          Shadow(
            color: MatrixTheme.matrixGreen.withValues(alpha: 0.55),
            blurRadius: 12,
          ),
          Shadow(
            color: MatrixTheme.matrixAccent.withValues(alpha: 0.35),
            blurRadius: 18,
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: showAppBar
          ? AppBar(
              title: barTitle,
              actions: actions,
              elevation: 0,
              scrolledUnderElevation: 0,
              backgroundColor: theme.scaffoldBackgroundColor,
              foregroundColor: MatrixTheme.matrixGreen,
              surfaceTintColor: Colors.transparent,
              iconTheme: const IconThemeData(color: MatrixTheme.matrixGreen),
              actionsIconTheme:
                  const IconThemeData(color: MatrixTheme.matrixGreen),
            )
          : null,
      body: Container(
        height: MediaQuery.of(context).size.height,
        decoration: BoxDecoration(gradient: MatrixTheme.backgroundGradient),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class TerminalButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isPrimary;
  final IconData? icon;

  const TerminalButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.isPrimary = true,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary ? scheme.primary : scheme.surface,
          foregroundColor: isPrimary ? scheme.onPrimary : scheme.primary,
          side: BorderSide(
            color: scheme.primary,
            width: isPrimary ? 0 : 2,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          elevation: 0,
        ),
        child: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isPrimary ? scheme.onPrimary : scheme.primary,
                  ),
                  strokeWidth: 2,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    text,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: isPrimary ? scheme.onPrimary : scheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
      ),
    );
  }
}

class TerminalTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool isPassword;
  final bool enabled;
  final String? Function(String?)? validator;
  final VoidCallback? onSuffixPressed;
  final IconData? suffixIcon;

  const TerminalTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.isPassword = false,
    this.enabled = true,
    this.validator,
    this.onSuffixPressed,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        TextFormField(
          enabled: enabled,
          controller: controller,
          obscureText: isPassword,
          style: Theme.of(context).textTheme.bodyLarge,
          decoration: MatrixTheme.getInputDecoration(
            hintText: hint,
            prefixIcon: icon,
            suffixIcon: suffixIcon,
            onSuffixPressed: onSuffixPressed,
            isDarkMode: isDark,
          ),
          validator: validator,
        ),
      ],
    );
  }
}

class TerminalStatusMessage extends StatelessWidget {
  final String message;
  final bool isError;
  final bool isWarning;
  final bool isSuccess;

  const TerminalStatusMessage({
    super.key,
    required this.message,
    this.isError = false,
    this.isWarning = false,
    this.isSuccess = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Color color = scheme.primary;
    if (isError) color = scheme.error;
    if (isWarning) color = MatrixTheme.warningOrange;
    if (isSuccess) color = MatrixTheme.successGreen;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1),
        borderRadius: BorderRadius.circular(4),
        color: scheme.surface.withValues(alpha: 0.8),
      ),
      child: Row(
        children: [
          Icon(
            isError
                ? Icons.error_outline
                : isWarning
                    ? Icons.warning_outlined
                    : isSuccess
                        ? Icons.check_circle_outline
                        : Icons.info_outline,
            color: color,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
