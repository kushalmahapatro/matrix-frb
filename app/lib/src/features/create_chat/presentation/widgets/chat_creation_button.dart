import 'package:flutter/material.dart';
import 'package:matrix/src/features/create_chat/domain/models/create_chat_type.dart';
import 'package:matrix/src/theme/matrix_theme.dart';

class ChatCreationButton extends StatelessWidget {
  const ChatCreationButton({
    super.key,
    required this.type,
    required this.label,
    required this.icon,
    required this.onTap,
    required this.isSelected,
  });
  final CreateChatType type;
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? MatrixTheme.primaryGreen.withValues(alpha: 0.2)
              : Colors.grey[900],
          border: Border.all(
            color: isSelected ? MatrixTheme.primaryGreen : Colors.transparent,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? MatrixTheme.primaryGreen : Colors.grey,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: MatrixTheme.bodyStyle.copyWith(
                color: isSelected ? MatrixTheme.primaryGreen : Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
