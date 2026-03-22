import 'package:flutter/material.dart';
import 'package:matrix/src/theme/matrix_theme.dart';
import 'package:matrix_sdk/matrix_sdk.dart';

class UserTile extends StatelessWidget {
  const UserTile({
    super.key,
    required this.user,
    required this.trailing,
    this.compact = false,
    this.terminalStyle = false,
  });
  final User user;
  final Widget trailing;
  final bool compact;
  /// Matrix terminal palette (square tile, green accent) for directory / new-chat flows.
  final bool terminalStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avatarRadius = compact ? 18.0 : 22.0;
    final pad = compact ? 10.0 : 12.0;
    final radius = terminalStyle
        ? BorderRadius.zero
        : BorderRadius.circular(compact ? 10 : 8);
    final Color bg;
    final Color borderColor;
    final Color avatarBg;
    final Color avatarFg;
    if (terminalStyle) {
      bg = MatrixTheme.terminalBackground.withValues(alpha: 0.92);
      borderColor = MatrixTheme.terminalBorder;
      avatarBg = MatrixTheme.matrixDarkGreen;
      avatarFg = MatrixTheme.matrixGreen;
    } else {
      bg = theme.colorScheme.surfaceContainerHighest;
      borderColor = Colors.transparent;
      avatarBg = theme.colorScheme.primary;
      avatarFg = theme.colorScheme.onPrimary;
    }
    return Container(
      margin: EdgeInsets.only(bottom: compact ? 6 : 8),
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radius,
        border: Border.all(color: borderColor, width: terminalStyle ? 1 : 0),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: avatarRadius,
            backgroundColor: avatarBg,
            foregroundColor: avatarFg,
            child: Text(
              user.displayName?.isNotEmpty == true
                  ? user.displayName![0].toUpperCase()
                  : (user.userId.length > 1 ? user.userId[1] : '@').toUpperCase(),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: compact ? 13 : 14,
              ),
            ),
          ),
          SizedBox(width: compact ? 10 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName?.isNotEmpty == true
                      ? user.displayName!
                      : user.userIdDisplay,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: terminalStyle ? MatrixTheme.matrixLightGreen : null,
                    fontFamily:
                        terminalStyle ? MatrixTheme.fontFamily : null,
                  ),
                ),
                if (user.displayName != null && user.displayName!.isNotEmpty)
                  Text(
                    user.userIdDisplay,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: terminalStyle ? MatrixTheme.matrixDarkGreen : null,
                      fontFamily:
                          terminalStyle ? MatrixTheme.fontFamily : null,
                    ),
                  ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}
