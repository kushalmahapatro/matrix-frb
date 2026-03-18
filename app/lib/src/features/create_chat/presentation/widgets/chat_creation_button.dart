import 'package:flutter/material.dart';
import 'package:matrix/src/features/create_chat/domain/models/create_chat_type.dart';

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
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final muted = theme.colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? primary.withValues(alpha: 0.2)
              : theme.colorScheme.surfaceContainerHighest,
          border: Border.all(
            color: isSelected ? primary : Colors.transparent,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? primary : muted,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isSelected ? primary : muted,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
