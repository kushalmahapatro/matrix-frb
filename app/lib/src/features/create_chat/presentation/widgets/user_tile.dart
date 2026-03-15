import 'package:flutter/material.dart';
import 'package:matrix/src/theme/matrix_theme.dart';
import 'package:matrix_sdk/matrix_sdk.dart';

class UserTile extends StatelessWidget {
  const UserTile({super.key, required this.user, required this.trailing});
  final User user;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MatrixTheme.colors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: MatrixTheme.primaryGreen,
            child: Text(
              user.displayName?.isNotEmpty == true
                  ? user.displayName![0].toUpperCase()
                  : user.userId[1].toUpperCase(),
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName ?? user.userId,
                  style: MatrixTheme.bodyStyle.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (user.displayName != null)
                  Text(user.userId, style: MatrixTheme.labelStyle),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}
