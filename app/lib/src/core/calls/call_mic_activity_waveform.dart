import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Visual mic activity (driven by captured PCM level in [0,1]).
///
/// Rebuild the parent (e.g. [ListenableBuilder] on [NativeLiveKitCallSession]) at ~15–30 Hz
/// for smooth motion; the painter adds a light phase animation from [animationSeed].
class CallMicActivityWaveform extends StatelessWidget {
  const CallMicActivityWaveform({
    super.key,
    required this.level,
    required this.muted,
    this.height = 36,
    this.barWidth = 3,
    this.gap = 2,
    this.activeColor = const Color(0xFF69F0AE),
    this.inactiveColor = const Color(0x33FFFFFF),
  });

  /// Smoothed peak level in \[0, 1\].
  final double level;

  final bool muted;
  final double height;
  final double barWidth;
  final double gap;
  final Color activeColor;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        if (!w.isFinite || w <= 0) {
          return SizedBox(height: height);
        }
        final step = barWidth + gap;
        final n = math.max(8, (w / step).floor());
        final t = DateTime.now().millisecondsSinceEpoch / 1000.0;
        return CustomPaint(
          size: Size(w, height),
          painter: _MicWaveformPainter(
            barCount: n,
            barWidth: barWidth,
            gap: gap,
            level: muted ? 0.0 : level.clamp(0.0, 1.0),
            phase: t * 7.0,
            activeColor: activeColor,
            inactiveColor: inactiveColor,
          ),
        );
      },
    );
  }
}

final class _MicWaveformPainter extends CustomPainter {
  _MicWaveformPainter({
    required this.barCount,
    required this.barWidth,
    required this.gap,
    required this.level,
    required this.phase,
    required this.activeColor,
    required this.inactiveColor,
  });

  final int barCount;
  final double barWidth;
  final double gap;
  final double level;
  final double phase;
  final Color activeColor;
  final Color inactiveColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..strokeCap = StrokeCap.round;
    final midY = size.height / 2;
    final maxHalf = midY - 2;
    for (var i = 0; i < barCount; i++) {
      final x = i * (barWidth + gap) + barWidth / 2;
      if (x > size.width) break;
      // Envelope: center bars slightly taller; motion from phase.
      final wobble =
          0.35 + 0.65 * (0.5 + 0.5 * math.sin(phase + i * 0.55)).abs();
      final h = level <= 0.002
          ? 2.0
          : (2.0 + maxHalf * level * wobble).clamp(2.0, maxHalf * 2);
      paint.color = level <= 0.002 ? inactiveColor : activeColor;
      paint.strokeWidth = barWidth;
      canvas.drawLine(
        Offset(x, midY - h / 2),
        Offset(x, midY + h / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MicWaveformPainter oldDelegate) {
    return oldDelegate.level != level ||
        oldDelegate.phase != phase ||
        oldDelegate.barCount != barCount ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor;
  }
}
