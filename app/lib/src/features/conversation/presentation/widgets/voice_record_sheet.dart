import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Result of [VoiceRecordSheet] when the user sends a recording.
class VoiceRecordResult {
  const VoiceRecordResult({
    required this.path,
    required this.durationMs,
    required this.waveform,
  });

  final String path;
  final int durationMs;

  /// Normalized 0..1 samples for Matrix `org.matrix.msc1767.audio` (downsampled).
  final List<double> waveform;

  /// Peak-preserving downsample for MSC waveform (max ~100 points).
  static List<double> downsample(List<double> samples, int targetBins) {
    if (samples.isEmpty || targetBins <= 0) return const [];
    if (samples.length <= targetBins) return List<double>.from(samples);
    final out = List<double>.filled(targetBins, 0);
    final bucket = samples.length / targetBins;
    for (var i = 0; i < targetBins; i++) {
      final start = (i * bucket).floor();
      final end = ((i + 1) * bucket).ceil().clamp(start + 1, samples.length);
      var maxV = 0.0;
      for (var j = start; j < end; j++) {
        final s = samples[j];
        if (s > maxV) maxV = s;
      }
      out[i] = maxV;
    }
    return out;
  }
}

/// Bottom sheet: record a voice clip with a live waveform, then send or discard.
///
/// Pops with [VoiceRecordResult], or `null` if cancelled.
class VoiceRecordSheet extends StatefulWidget {
  const VoiceRecordSheet({super.key});

  @override
  State<VoiceRecordSheet> createState() => _VoiceRecordSheetState();
}

class _VoiceRecordSheetState extends State<VoiceRecordSheet> {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Amplitude>? _ampSub;
  /// Last [_barCount] samples for the live UI.
  final List<double> _displaySamples = [];
  /// All samples while recording (for send).
  final List<double> _fullSamples = [];
  DateTime? _recordStart;
  /// Wall-clock recording length at stop (for Matrix `msc1767.audio` duration).
  int? _stoppedDurationMs;

  bool _recording = false;
  bool _busy = false;
  String? _recordedPath;
  Duration _elapsed = Duration.zero;
  Timer? _tick;
  /// `true` after [Navigator.pop] with a path so [dispose] does not delete the file.
  bool _handedOffFile = false;

  static const int _barCount = 44;
  static const int _waveformSendBins = 96;

  @override
  void dispose() {
    _tick?.cancel();
    unawaited(() async {
      await _ampSub?.cancel();
      if (_recording) {
        await _recorder.cancel();
      } else if (_recordedPath != null && !_handedOffFile) {
        try {
          final f = File(_recordedPath!);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      await _recorder.dispose();
    }());
    super.dispose();
  }

  double _normalizeDb(double db) {
    const minDb = -55.0;
    const maxDb = -8.0;
    if (db <= minDb) return 0.06;
    if (db >= maxDb) return 1.0;
    return ((db - minDb) / (maxDb - minDb)).clamp(0.06, 1.0);
  }

  Future<void> _startRecording() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await _recorder.hasPermission();
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Microphone permission is required to record.'),
            ),
          );
        }
        setState(() => _busy = false);
        return;
      }
      final dir = await getTemporaryDirectory();
      final outPath = p.join(
        dir.path,
        'matrix_voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
      );
      final enc = AudioEncoder.aacLc;
      if (!await _recorder.isEncoderSupported(enc)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Voice recording is not supported on this device.'),
            ),
          );
        }
        setState(() => _busy = false);
        return;
      }

      _displaySamples.clear();
      _fullSamples.clear();
      _recordStart = null;
      _stoppedDurationMs = null;
      await _ampSub?.cancel();
      _ampSub = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 90))
          .listen((amp) {
        if (!mounted) return;
        var n = _normalizeDb(amp.current);
        // Desktop amplitude streams are often flat; add motion so the UI matches expectations.
        if (!kIsWeb &&
            (Platform.isLinux ||
                Platform.isMacOS ||
                Platform.isWindows)) {
          final t = DateTime.now().millisecondsSinceEpoch / 185.0;
          final shimmer = 0.14 * math.sin(t);
          n = (n + shimmer).clamp(0.08, 1.0);
        }
        setState(() {
          _fullSamples.add(n);
          _displaySamples.add(n);
          while (_displaySamples.length > _barCount) {
            _displaySamples.removeAt(0);
          }
        });
      });

      await _recorder.start(
        RecordConfig(
          encoder: enc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: outPath,
      );

      _elapsed = Duration.zero;
      _recordStart = DateTime.now();
      _tick?.cancel();
      setState(() {
        _recording = true;
        _recordedPath = null;
        _busy = false;
      });
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _elapsed += const Duration(seconds: 1));
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start recording: $e')),
        );
      }
      setState(() {
        _busy = false;
        _recording = false;
      });
    }
  }

  Future<void> _stopRecording() async {
    if (!_recording || _busy) return;
    _tick?.cancel();
    _tick = null;
    setState(() => _busy = true);
    try {
      final path = await _recorder.stop();
      await _ampSub?.cancel();
      _ampSub = null;
      if (mounted) {
        final durMs = _recordStart != null
            ? DateTime.now().difference(_recordStart!).inMilliseconds
            : _elapsed.inMilliseconds;
        setState(() {
          _recording = false;
          _busy = false;
          _recordedPath = path;
          _stoppedDurationMs = durMs > 0 ? durMs : 1;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _recording = false;
          _busy = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Stop failed: $e')),
        );
      }
    }
  }

  Future<void> _discardRecording() async {
    final path = _recordedPath;
    setState(() {
      _recordedPath = null;
      _elapsed = Duration.zero;
    });
    if (path != null) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    _displaySamples.clear();
    _fullSamples.clear();
    _recordStart = null;
    _stoppedDurationMs = null;
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _waveform(ThemeData theme) {
    final scheme = theme.colorScheme;
    final heights = List<double>.generate(_barCount, (i) {
      final idx = _displaySamples.length - _barCount + i;
      if (idx < 0) return 0.08;
      return _displaySamples[idx].clamp(0.0, 1.0);
    });
    return SizedBox(
      height: 72,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(_barCount, (i) {
          final h = 6 + heights[i] * 58;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0.5),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 90),
                  height: h,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(
                      alpha: _recording ? 0.9 : 0.55,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom + 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Voice message',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _busy
                      ? null
                      : () {
                          Navigator.of(context).pop<VoiceRecordResult?>(null);
                        },
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: scheme.outlineVariant),
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.mic_rounded,
                          size: 22,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatDuration(_elapsed),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _waveform(theme),
                    const SizedBox(height: 18),
                    if (_recordedPath == null)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (!_recording)
                            FilledButton.icon(
                              onPressed: _busy ? null : _startRecording,
                              icon: const Icon(Icons.fiber_manual_record),
                              label: const Text('Record'),
                            )
                          else
                            FilledButton.tonalIcon(
                              onPressed: _busy ? null : _stopRecording,
                              style: FilledButton.styleFrom(
                                foregroundColor: scheme.error,
                              ),
                              icon: const Icon(Icons.stop_rounded),
                              label: const Text('Stop'),
                            ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      await _discardRecording();
                                      if (mounted) setState(() {});
                                    },
                              child: const Text('Re-record'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      final path = _recordedPath;
                                      if (path == null || path.isEmpty) {
                                        return;
                                      }
                                      if (!await File(path).exists()) {
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Recording file is missing.',
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                      if (!context.mounted) return;
                                      final durationMs =
                                          _stoppedDurationMs ??
                                          _elapsed.inMilliseconds;
                                      final wf = VoiceRecordResult.downsample(
                                        _fullSamples,
                                        _waveformSendBins,
                                      );
                                      _handedOffFile = true;
                                      Navigator.of(context).pop<VoiceRecordResult>(
                                        VoiceRecordResult(
                                          path: path,
                                          durationMs: durationMs > 0
                                              ? durationMs
                                              : 1,
                                          waveform: wf,
                                        ),
                                      );
                                    },
                              icon: const Icon(Icons.send, size: 20),
                              label: const Text('Send'),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
