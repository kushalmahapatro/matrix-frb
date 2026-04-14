import 'dart:io';

import 'package:flutter/material.dart';
import 'package:matrix/src/core/matrix_media_kit_video.dart';
import 'package:matrix/src/features/conversation/presentation/widgets/audio_message_waveform.dart';
import 'package:matrix/src/core/video_send_media_prep.dart';
import 'package:media/media.dart' show EncodeTimeEstimate;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:matrix_sdk/matrix_sdk.dart'
    show FileSendPhase, FileSendProgress;
import 'package:result_dart/result_dart.dart';

/// Preview + explicit Send. Video: thumbnail + play → inline player; HD/SD quality (default SD).
class MediaOutgoingSendScreen extends StatefulWidget {
  const MediaOutgoingSendScreen({
    super.key,
    required this.title,
    required this.filePath,
    this.mimeType,
    this.caption,
    this.audioDurationMs,
    this.audioWaveformNormalized,
    this.audioAsVoiceMessage = false,
    required this.sendAttachment,
    required this.onCancelSend,
  });

  final String title;
  final String filePath;
  final String? caption;
  final int? audioDurationMs;
  final List<double>? audioWaveformNormalized;
  final bool audioAsVoiceMessage;

  final String? mimeType;

  final Future<Result<Unit>> Function({
    AppTimelineSendPrep? prep,
    required String originalFilePath,
    required void Function(FileSendProgress p) onProgress,
    int? audioDurationMs,
    List<double>? audioWaveformNormalized,
    required bool audioAsVoiceMessage,
  }) sendAttachment;

  final void Function() onCancelSend;

  @override
  State<MediaOutgoingSendScreen> createState() =>
      _MediaOutgoingSendScreenState();
}

class _MediaOutgoingSendScreenState extends State<MediaOutgoingSendScreen> {
  bool _finished = false;
  bool _estimatingVideo = false;
  bool _estimateDone = false;
  int? _estimateHd720Bytes;
  int? _estimateSd480Bytes;
  EncodeTimeEstimate? _encodeEstHd720;
  EncodeTimeEstimate? _encodeEstSd480;

  double? _videoTranscodeLinear;
  bool _videoTranscodePastEstimate = false;
  String? _videoTranscodeMsg;

  int? _originalFileBytes;
  bool _videoThumbLoading = false;
  String? _previewThumbPath;
  bool _videoPlayback = false;

  VideoSendQuality _videoQuality = VideoSendQuality.sd;

  bool _sending = false;
  MediaOutboundPrepStage? _prepStage;
  FileSendProgress? _rustProgress;
  String? _error;

  bool get _isVideo => _isVideoFile(widget.filePath, widget.mimeType);

  bool get _isAudio => _isAudioFile(widget.filePath, widget.mimeType);

  @override
  void initState() {
    super.initState();
    _loadFileMetaAndPreview();
    _runInitialEstimate();
  }

  @override
  void dispose() {
    final thumb = _previewThumbPath;
    if (thumb != null) {
      try {
        File(thumb).deleteSync();
      } catch (_) {}
    }
    super.dispose();
  }

  void _cancelBecauseUserLeft() {
    if (_finished) return;
    _finished = true;
    widget.onCancelSend();
  }

  Future<void> _loadFileMetaAndPreview() async {
    final f = File(widget.filePath);
    if (!await f.exists()) return;
    final len = await f.length();
    if (!mounted) return;
    setState(() => _originalFileBytes = len);

    if (!_isVideo) return;
    setState(() => _videoThumbLoading = true);
    try {
      final path = await generateVideoPreviewThumbnailForUi(widget.filePath);
      if (!mounted) return;
      setState(() {
        _previewThumbPath = path;
        _videoThumbLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _videoThumbLoading = false);
    }
  }

  Future<void> _runInitialEstimate() async {
    if (!_isVideo) {
      setState(() {
        _estimateDone = true;
        _estimatingVideo = false;
      });
      return;
    }
    setState(() {
      _estimatingVideo = true;
      _estimateDone = false;
    });
    try {
      final est = await estimateVideoHdSdForTimelineSend(widget.filePath);
      if (!mounted) return;
      setState(() {
        _estimateHd720Bytes = est.sizes.hd720Bytes;
        _estimateSd480Bytes = est.sizes.sd480Bytes;
        _encodeEstHd720 = est.hd720Encode;
        _encodeEstSd480 = est.sd480Encode;
        _estimatingVideo = false;
        _estimateDone = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _estimateHd720Bytes = null;
        _estimateSd480Bytes = null;
        _encodeEstHd720 = null;
        _encodeEstSd480 = null;
        _estimatingVideo = false;
        _estimateDone = true;
      });
    }
  }

  bool get _canSend {
    if (_sending || _finished) return false;
    if (_isVideo) {
      return _estimateDone && !_estimatingVideo;
    }
    return true;
  }

  int? get _selectedEstimateBytes => _videoQuality == VideoSendQuality.hd
      ? _estimateHd720Bytes
      : _estimateSd480Bytes;

  Future<void> _onSendPressed() async {
    if (!_canSend) return;
    setState(() {
      _sending = true;
      _error = null;
      _prepStage = null;
      _rustProgress = null;
      _videoTranscodeLinear = null;
      _videoTranscodePastEstimate = false;
      _videoTranscodeMsg = null;
    });
    AppTimelineSendPrep? prep;
    try {
      prep = await AppTimelineSendPrep.prepareForSend(
        widget.filePath,
        mimeType: widget.mimeType,
        encodeWallClockEstimate: _videoQuality == VideoSendQuality.hd
            ? _encodeEstHd720
            : _encodeEstSd480,
        onStage: (s) {
          if (!mounted) return;
          setState(() {
            _prepStage = s;
            if (s != MediaOutboundPrepStage.compressingVideo) {
              _videoTranscodeLinear = null;
              _videoTranscodePastEstimate = false;
              _videoTranscodeMsg = null;
            }
          });
        },
        onVideoTranscodeProgress: (c) {
          if (!mounted) return;
          setState(() {
            if (c.linearProgress != null) {
              _videoTranscodeLinear = c.linearProgress;
            }
            if (c.pastEstimate != null) {
              _videoTranscodePastEstimate = c.pastEstimate!;
            }
            if (c.message != null) {
              _videoTranscodeMsg = c.message;
            }
          });
        },
        videoQuality: _videoQuality,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _sending = false;
      });
      return;
    }

    if (await isTimelineVideoSendCandidate(
      widget.filePath,
      mimeType: widget.mimeType,
    )) {
      final thumb = prep?.appThumbnailJpegPath;
      if (prep == null || thumb == null || thumb.isEmpty) {
        prep?.dispose();
        if (!mounted) return;
        setState(() {
          _error =
              'Video send requires a JPEG thumbnail. Preparation failed — try another clip.';
          _sending = false;
        });
        return;
      }
    }

    try {
      final r = await widget.sendAttachment(
        prep: prep,
        originalFilePath: widget.filePath,
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _rustProgress = p);
        },
        audioDurationMs: widget.audioDurationMs,
        audioWaveformNormalized: widget.audioWaveformNormalized,
        audioAsVoiceMessage: widget.audioAsVoiceMessage,
      );
      prep = null;
      if (!mounted) return;
      r.fold(
        (_) {
          _finished = true;
          Navigator.of(context).pop(true);
        },
        (f) {
          setState(() {
            _error = f.toString();
            _rustProgress = null;
            _sending = false;
          });
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _rustProgress = null;
        _sending = false;
      });
    }
  }

  String _prepStageLabel(MediaOutboundPrepStage s) {
    return switch (s) {
      MediaOutboundPrepStage.compressingVideo => 'Compressing video',
      MediaOutboundPrepStage.generatingThumbnail => 'Generating thumbnail',
    };
  }

  String _rustPhaseLabel(FileSendPhase phase) {
    return switch (phase) {
      FileSendPhase.videoCompress => 'Preparing media',
      FileSendPhase.mainUpload => 'Uploading media',
      FileSendPhase.thumbnailUpload => 'Uploading thumbnail',
      FileSendPhase.sendingMessage => 'Sending message',
      FileSendPhase.encryptedQueued => 'Encrypting attachment',
      FileSendPhase.done => 'Done',
      FileSendPhase.cancelled => 'Cancelled',
      FileSendPhase.failed => 'Failed',
    };
  }

  double? _ratio(FileSendProgress p) {
    if (p.phase == FileSendPhase.encryptedQueued) return null;
    final t = p.total;
    if (t <= BigInt.zero) return null;
    final scaled = (p.current * BigInt.from(10_000)) ~/ t;
    return scaled.toInt().clamp(0, 10_000) / 10_000.0;
  }

  String _bytesLabel(FileSendProgress p) {
    if (p.total <= BigInt.zero) return 'Working…';
    return '${p.current} / ${p.total} bytes';
  }

  String _formatSize(int? bytes) {
    if (bytes == null) return '—';
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb >= 100 ? 0 : 1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
  }

  String _formatEncodeEta(EncodeTimeEstimate? e) {
    if (e == null) return '—';
    final ms = e.estimated.inMilliseconds;
    if (ms <= 0) return '—';
    return '~${e.estimatedSeconds.toStringAsFixed(0)} s (${e.confidence.name})';
  }

  Widget _prepStageProgressBar(ThemeData theme) {
    final stage = _prepStage;
    if (stage == null) {
      return const SizedBox.shrink();
    }
    if (stage != MediaOutboundPrepStage.compressingVideo) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: LinearProgressIndicator(),
      );
    }

    final selEta = _videoQuality == VideoSendQuality.hd
        ? _encodeEstHd720
        : _encodeEstSd480;
    final etaMs = selEta?.estimated.inMilliseconds ?? 0;
    final timeBased = etaMs > 0;
    final linear = (_videoTranscodeLinear ?? 0).clamp(0.0, 1.0);

    if (timeBased && selEta != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_videoTranscodePastEstimate)
              const LinearProgressIndicator()
            else
              LinearProgressIndicator(value: linear),
            const SizedBox(height: 6),
            Text(
              _videoTranscodePastEstimate
                  ? 'Past ~${selEta.estimatedSeconds.toStringAsFixed(0)} s estimate — still encoding…'
                  : '${(linear * 100).toStringAsFixed(0)}% of ~${selEta.estimatedSeconds.toStringAsFixed(0)} s '
                      '(${selEta.confidence.name})',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (_videoTranscodeMsg != null && _videoTranscodeMsg!.trim().isNotEmpty)
              Text(
                _videoTranscodeMsg!,
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(
            value: (_videoTranscodeLinear != null && _videoTranscodeLinear! > 0)
                ? _videoTranscodeLinear!.clamp(0.0, 1.0)
                : null,
          ),
          const SizedBox(height: 6),
          Text(
            'No time estimate (unknown duration) — native progress when available.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (_videoTranscodeMsg != null && _videoTranscodeMsg!.trim().isNotEmpty)
            Text(
              _videoTranscodeMsg!,
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget _estimateRow(
    ThemeData theme, {
    required String label,
    required int? bytes,
    bool emphasize = false,
  }) {
    final valueStyle = theme.textTheme.bodySmall?.copyWith(
      fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
      color: emphasize ? theme.colorScheme.primary : null,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        SizedBox(
          width: 108,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            _estimatingVideo ? '…' : _formatSize(bytes),
            style: valueStyle,
          ),
        ),
      ],
    );
  }

  Widget _buildPreview(ThemeData theme) {
    final isImage = _isImageFile(widget.filePath, widget.mimeType);
    if (isImage) {
      return Padding(
        padding: const EdgeInsets.all(10),
        child: Center(
          child: Image.file(
            File(widget.filePath),
            fit: BoxFit.contain,
          ),
        ),
      );
    }
    if (_isVideo) {
      if (_videoPlayback) {
        return _OutgoingInlineVideo(filePath: widget.filePath);
      }
      if (_videoThumbLoading && _previewThumbPath == null) {
        return Center(
          child: CircularProgressIndicator(
            color: theme.colorScheme.primary,
          ),
        );
      }
      if (_previewThumbPath != null) {
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(_previewThumbPath!),
              fit: BoxFit.contain,
            ),
            Center(
              child: Material(
                color: Colors.black45,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => setState(() => _videoPlayback = true),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      size: 56,
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      }
      return Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: theme.colorScheme.surfaceContainerHigh,
            child: Icon(
              Icons.videocam_outlined,
              size: 72,
              color: theme.colorScheme.outline,
            ),
          ),
          Center(
            child: Material(
              color: Colors.black45,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => setState(() => _videoPlayback = true),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    size: 56,
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    if (_isAudio) {
      final wf = widget.audioWaveformNormalized;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.graphic_eq_rounded,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 10),
            Text(
              'Voice message',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (wf != null && wf.isNotEmpty) ...[
              const SizedBox(height: 14),
              AudioMessageWaveformBars(
                samples: wf,
                height: 56,
                width: 220,
              ),
            ],
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                p.basename(widget.filePath),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.insert_drive_file_outlined,
            size: 64,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              p.basename(widget.filePath),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isImage = _isImageFile(widget.filePath, widget.mimeType);
    final isAudio = _isAudioFile(widget.filePath, widget.mimeType);

    return PopScope<Object?>(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) return;
        if (_finished) return;
        if (result == true) return;
        _cancelBecauseUserLeft();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              if (!_finished && _sending) {
                widget.onCancelSend();
              }
              if (!_finished) {
                _finished = true;
              }
              Navigator.of(context).pop(false);
            },
          ),
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                      color: theme.colorScheme.surfaceContainerHighest,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: _buildPreview(theme),
                    ),
                  ),
                ),
              ),
              if (isImage || isAudio)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'File size: ${_formatSize(_originalFileBytes)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (_isVideo) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'Original file size: ${_formatSize(_originalFileBytes)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SegmentedButton<VideoSendQuality>(
                    segments: const [
                      ButtonSegment<VideoSendQuality>(
                        value: VideoSendQuality.sd,
                        label: Text('SD'),
                        tooltip: '480p',
                      ),
                      ButtonSegment<VideoSendQuality>(
                        value: VideoSendQuality.hd,
                        label: Text('HD'),
                        tooltip: '720p',
                      ),
                    ],
                    selected: {_videoQuality},
                    onSelectionChanged: (s) {
                      setState(() => _videoQuality = s.first);
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text(
                    'Estimated size after compression',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _estimateRow(
                        theme,
                        label: 'HD (720p)',
                        bytes: _estimateHd720Bytes,
                        emphasize: _videoQuality == VideoSendQuality.hd,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 108, top: 2, bottom: 4),
                        child: Text(
                          _estimatingVideo
                              ? '…'
                              : 'Wall time (est.): ${_formatEncodeEta(_encodeEstHd720)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: _videoQuality == VideoSendQuality.hd
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outline,
                            fontWeight: _videoQuality == VideoSendQuality.hd
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                      _estimateRow(
                        theme,
                        label: 'SD (480p)',
                        bytes: _estimateSd480Bytes,
                        emphasize: _videoQuality == VideoSendQuality.sd,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 108, top: 2, bottom: 4),
                        child: Text(
                          _estimatingVideo
                              ? '…'
                              : 'Wall time (est.): ${_formatEncodeEta(_encodeEstSd480)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: _videoQuality == VideoSendQuality.sd
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outline,
                            fontWeight: _videoQuality == VideoSendQuality.sd
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (_estimatingVideo) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Estimating…',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'Selected quality (~${_videoQuality == VideoSendQuality.hd ? '720p' : '480p'}): '
                    '${_estimatingVideo ? '…' : _formatSize(_selectedEstimateBytes)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              if (widget.caption != null && widget.caption!.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    widget.caption!.trim(),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _error!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              if (_sending) ...[
                if (_prepStage != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(
                      _prepStageLabel(_prepStage!),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (_prepStage != null) _prepStageProgressBar(theme),
                if (_rustProgress != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      _rustPhaseLabel(_rustProgress!.phase),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: LinearProgressIndicator(
                      value: _ratio(_rustProgress!),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Text(
                      _bytesLabel(_rustProgress!),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ] else if (_prepStage == null && _error == null)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: _canSend ? _onSendPressed : null,
                  icon: const Icon(Icons.send),
                  label: Text(_sending ? 'Sending…' : 'Send'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isVideoFile(String path, String? mime) {
    final m = mime?.toLowerCase().trim();
    if (m != null && m.startsWith('video/')) return true;
    return isProbableVideoFilePath(path);
  }

  bool _isImageFile(String path, String? mime) {
    final m = mime?.toLowerCase().trim();
    if (m != null && m.startsWith('image/')) return true;
    return isProbableRasterImageFilePath(path);
  }

  bool _isAudioFile(String path, String? mime) {
    final m = mime?.toLowerCase().trim();
    if (m != null && m.startsWith('audio/')) return true;
    final ext = p.extension(path).toLowerCase();
    return ext == '.m4a' ||
        ext == '.aac' ||
        ext == '.mp3' ||
        ext == '.ogg' ||
        ext == '.opus' ||
        ext == '.wav' ||
        ext == '.flac';
  }
}

/// In-place playback for the send preview; [Player] disposed with this widget.
class _OutgoingInlineVideo extends StatefulWidget {
  const _OutgoingInlineVideo({required this.filePath});

  final String filePath;

  @override
  State<_OutgoingInlineVideo> createState() => _OutgoingInlineVideoState();
}

class _OutgoingInlineVideoState extends State<_OutgoingInlineVideo> {
  late final Player _player = Player();
  late final VideoController _videoController = VideoController(
    _player,
    configuration: matrixPlaybackVideoControllerConfiguration(),
  );
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      await matrixAwaitVideoControllerPlatformReady(_videoController);
      await _player.open(Media(Uri.file(widget.filePath).toString()));
      if (mounted) setState(() => _opened = true);
    } catch (_) {
      if (mounted) setState(() => _opened = false);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_opened) {
      return Center(
        child: CircularProgressIndicator(
          color: Theme.of(context).colorScheme.primary,
        ),
      );
    }
    return Video(
      controller: _videoController,
      controls: AdaptiveVideoControls,
    );
  }
}
