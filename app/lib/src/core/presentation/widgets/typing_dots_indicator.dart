import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Three pulsing dots (common chat “typing” affordance).
class TypingDotsIndicator extends StatefulWidget {
  const TypingDotsIndicator({
    super.key,
    this.color,
    this.dotSize = 5,
    this.spacing = 4,
  });

  final Color? color;
  final double dotSize;
  final double spacing;

  @override
  State<TypingDotsIndicator> createState() => _TypingDotsIndicatorState();
}

class _TypingDotsIndicatorState extends State<TypingDotsIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _opacityForDot(int index, double t) {
    // Stagger each dot by 1/3 of a cycle.
    final shifted = (t + index / 3) % 1.0;
    return (0.35 +
            0.65 * (math.sin(shifted * math.pi * 2) * 0.5 + 0.5))
        .clamp(0.35, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.color ?? Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            return Padding(
              padding: EdgeInsets.only(right: i < 2 ? widget.spacing : 0),
              child: Opacity(
                opacity: _opacityForDot(i, t),
                child: Container(
                  width: widget.dotSize,
                  height: widget.dotSize,
                  decoration: BoxDecoration(
                    color: base,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

/// Resolves a display name from [map] using an exact key, then a case-insensitive MXID match.
String? memberDisplayNameForUserId(Map<String, String> map, String userId) {
  final key = userId.trim();
  if (key.isEmpty) return null;
  final direct = map[key]?.trim();
  if (direct != null && direct.isNotEmpty) return direct;
  final lower = key.toLowerCase();
  for (final e in map.entries) {
    if (e.key.trim().toLowerCase() == lower) {
      final v = e.value.trim();
      if (v.isNotEmpty) return v;
    }
  }
  return null;
}

/// Short labels for Matrix user ids when member display names are unknown.
String typingUserIdsShortLabel(List<String> userIds) {
  if (userIds.isEmpty) return '';
  String shortId(String id) {
    final s = id.trim();
    if (s.startsWith('@')) {
      final colon = s.indexOf(':');
      if (colon > 1) return s.substring(1, colon);
    }
    return s.length > 18 ? '${s.substring(0, 16)}…' : s;
  }

  if (userIds.length == 1) {
    return '${shortId(userIds[0])} is typing';
  }
  if (userIds.length == 2) {
    return '${shortId(userIds[0])} & ${shortId(userIds[1])} are typing';
  }
  if (userIds.length == 3) {
    return '${shortId(userIds[0])}, ${shortId(userIds[1])} & '
        '${shortId(userIds[2])} are typing';
  }
  return '${userIds.length} people are typing';
}
