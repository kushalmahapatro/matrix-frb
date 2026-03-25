import 'package:flutter/material.dart';

/// Normalized bar heights when the event has no `org.matrix.msc1767.audio` waveform.
List<double> placeholderAudioWaveformBars(String key, {int barCount = 36}) {
  var h = key.hashCode;
  if (h == 0) h = 0x1a2b3c4d;
  return List.generate(barCount, (i) {
    h = (h * 0x9e3779b1 ^ i * 0x517cc1b7) & 0x7fffffff;
    return (0.2 + (h % 700) / 700.0 * 0.75).clamp(0.15, 0.98);
  });
}

/// Renders Matrix MSC-style normalized samples (0..1) as vertical bars.
class AudioMessageWaveformBars extends StatelessWidget {
  const AudioMessageWaveformBars({
    super.key,
    required this.samples,
    required this.height,
    this.width,
    this.barColor,
    this.backgroundColor,

    /// Softer bars when showing [placeholderAudioWaveformBars] (no server waveform).
    this.isPlaceholder = false,
  });

  final List<double> samples;
  final double height;
  final double? width;
  final Color? barColor;
  final Color? backgroundColor;
  final bool isPlaceholder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (samples.isEmpty) {
      return SizedBox(height: height, width: width ?? 48);
    }
    final w = width ?? 140;
    final base = barColor ?? theme.colorScheme.primary;
    final fgAlpha = isPlaceholder ? 0.62 : 0.95;
    final bg =
        backgroundColor ??
        theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.55);
    final innerH = (height - 14).clamp(12.0, 80.0);
    return SizedBox(
      width: w,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          color: bg,
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.45),
            width: 0.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(samples.length, (i) {
              final v = samples[i].clamp(0.0, 1.0);
              final barH = 5.0 + v * innerH;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 0.35),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      height: barH,
                      decoration: BoxDecoration(
                        color: base.withValues(alpha: fgAlpha),
                        borderRadius: BorderRadius.circular(1.2),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
