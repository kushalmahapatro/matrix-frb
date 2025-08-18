import 'package:flutter/material.dart';
import 'package:matrix/src/theme/matrix_theme.dart';

class TerminalContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final bool showBorder;
  final bool showGlow;
  final Color? borderColor;
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
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border:
            showBorder
                ? Border.all(
                  color: borderColor ?? MatrixTheme.matrixGreen,
                  width: 1,
                )
                : null,
        borderRadius: BorderRadius.circular(4),
        color: MatrixTheme.terminalBackground,
        boxShadow:
            showGlow
                ? [
                  BoxShadow(
                    color: (borderColor ?? MatrixTheme.matrixGreen).withValues(
                      alpha: 0.3,
                    ),
                    blurRadius: 10,
                    spreadRadius: 1,
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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar:
          showAppBar
              ? AppBar(
                title: Text(title ?? '', style: MatrixTheme.titleStyle),
                actions: actions,
                elevation: 0,
              )
              : null,
      body: Container(
        height: MediaQuery.of(context).size.height,
        decoration: BoxDecoration(gradient: MatrixTheme.backgroundGradient),
        child: SafeArea(child: child),
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
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor:
              isPrimary ? MatrixTheme.matrixGreen : MatrixTheme.terminalBlack,
          foregroundColor:
              isPrimary ? MatrixTheme.terminalBlack : MatrixTheme.matrixGreen,
          side: BorderSide(
            color: MatrixTheme.matrixGreen,
            width: isPrimary ? 0 : 2,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          elevation: 0,
        ),
        child:
            isLoading
                ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isPrimary
                          ? MatrixTheme.terminalBlack
                          : MatrixTheme.matrixGreen,
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
                      style: MatrixTheme.buttonStyle.copyWith(
                        color:
                            isPrimary
                                ? MatrixTheme.terminalBlack
                                : MatrixTheme.matrixGreen,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: MatrixTheme.labelStyle),
        const SizedBox(height: 8),
        TextFormField(
          enabled: enabled,
          controller: controller,
          obscureText: isPassword,
          style: MatrixTheme.inputStyle,
          decoration: MatrixTheme.inputDecoration(
            hintText: hint,
            prefixIcon: icon,
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
    Color color = MatrixTheme.matrixGreen;
    if (isError) color = MatrixTheme.errorRed;
    if (isWarning) color = MatrixTheme.warningOrange;
    if (isSuccess) color = MatrixTheme.successGreen;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1),
        borderRadius: BorderRadius.circular(4),
        color: MatrixTheme.terminalBlack.withValues(alpha: 0.8),
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
              style: MatrixTheme.statusStyle.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
