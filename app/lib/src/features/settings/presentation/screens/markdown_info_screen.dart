import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:matrix/src/core/presentation/widgets/terminal_container.dart';

/// Simple scrollable Markdown page (FAQ, credits, etc.).
class MarkdownInfoScreen extends StatelessWidget {
  const MarkdownInfoScreen({
    super.key,
    required this.title,
    required this.bodyMarkdown,
  });

  final String title;
  final String bodyMarkdown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TerminalScreen(
      title: title.toUpperCase(),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: TerminalContainer(
          child: MarkdownBody(
            data: bodyMarkdown,
            selectable: true,
            styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
              p: theme.textTheme.bodyMedium,
              h2: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
              horizontalRuleDecoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
