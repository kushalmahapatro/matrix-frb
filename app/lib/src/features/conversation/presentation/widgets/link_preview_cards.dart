import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:matrix/src/theme/matrix_theme.dart';

/// True when [json] is a non-empty JSON array (MSC4095 previews).
bool matrixLinkPreviewsJsonHasData(String json) {
  if (json.isEmpty || json == '[]') return false;
  try {
    final d = jsonDecode(json);
    return d is List && d.isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// Renders MSC4095 `com.beeper.linkpreviews` entries (og:title, og:description, URLs).
class MatrixLinkPreviewCards extends StatelessWidget {
  const MatrixLinkPreviewCards({
    super.key,
    required this.linkPreviewsJson,
    required this.accentColor,
    required this.onOpenUrl,
    this.compact = false,
  });

  final String linkPreviewsJson;
  final Color accentColor;
  final void Function(String url) onOpenUrl;
  final bool compact;

  List<Map<String, dynamic>> _parse() {
    try {
      final d = jsonDecode(linkPreviewsJson);
      if (d is! List) return [];
      return d
          .whereType<Map>()
          .map(
            (e) => Map<String, dynamic>.from(
              e.map((k, v) => MapEntry(k.toString(), v)),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  String? _s(Map<String, dynamic> m, String k) =>
      m[k] is String ? m[k] as String : null;

  String _tapUrl(Map<String, dynamic> m) =>
      _s(m, 'matched_url') ?? _s(m, 'og:url') ?? '';

  @override
  Widget build(BuildContext context) {
    final items = _parse();
    if (items.isEmpty) return const SizedBox.shrink();

    final top = compact ? 8.0 : 10.0;
    final gap = compact ? 6.0 : 8.0;
    final pad = compact ? 10.0 : 12.0;

    return Padding(
      padding: EdgeInsets.only(top: top),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!compact)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '// LINK_PREVIEW',
                style: MatrixTheme.labelStyle.copyWith(
                  fontSize: 10,
                  letterSpacing: 2,
                  color: accentColor.withValues(alpha: 0.85),
                ),
              ),
            ),
          ...items.map((m) {
            final title =
                _s(m, 'og:title') ?? _s(m, 'matched_url') ?? 'Link';
            final desc = _s(m, 'og:description');
            final urlLine = _s(m, 'og:url') ?? _s(m, 'matched_url');
            final tap = _tapUrl(m);

            return Padding(
              padding: EdgeInsets.only(bottom: gap),
              child: Material(
                color: MatrixTheme.terminalBlack.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(8),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: tap.isEmpty ? null : () => onOpenUrl(tap),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: accentColor.withValues(alpha: 0.4),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accentColor.withValues(alpha: 0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(pad),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.link_rounded,
                                size: compact ? 18 : 20,
                                color: accentColor.withValues(alpha: 0.95),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(
                                        color: MatrixTheme.matrixLightGreen,
                                        fontFamily: MatrixTheme.fontFamily,
                                        fontWeight: FontWeight.w700,
                                        height: 1.25,
                                      ),
                                ),
                              ),
                              Icon(
                                Icons.open_in_new_rounded,
                                size: 17,
                                color: MatrixTheme.matrixDarkGreen
                                    .withValues(alpha: 0.95),
                              ),
                            ],
                          ),
                          if (desc != null && desc.trim().isNotEmpty) ...[
                            SizedBox(height: compact ? 6 : 8),
                            Text(
                              desc.trim(),
                              maxLines: compact ? 2 : 4,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: MatrixTheme.matrixGreen
                                        .withValues(alpha: 0.9),
                                    fontFamily: MatrixTheme.fontFamily,
                                    height: 1.4,
                                  ),
                            ),
                          ],
                          if (urlLine != null && urlLine.isNotEmpty) ...[
                            SizedBox(height: compact ? 6 : 8),
                            Text(
                              urlLine,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color:
                                        accentColor.withValues(alpha: 0.92),
                                    fontFamily: MatrixTheme.fontFamily,
                                    fontSize: 11,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
