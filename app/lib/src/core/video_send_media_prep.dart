import 'dart:developer' as developer;
import 'dart:io';

import 'package:media/media.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Compress videos at or above this size before send (H.264/AAC MP4 via `media` package).
const int kVideoTranscodeMinBytes = 2 * 1024 * 1024;

/// Target bitrate for HD (720p) transcode — keep in sync with [CompressParams] for that preset.
const int kVideoTranscodeTargetBitrateKbps = 2000;

/// Target bitrate for SD (480p) transcode.
const int kVideoTranscodeSdBitrateKbps = 1200;

/// User-chosen output profile for timeline video send (see [prepareVideoForTimelineSend]).
enum VideoSendQuality {
  /// 854×480, [kVideoTranscodeSdBitrateKbps].
  sd,

  /// 1280×720, [kVideoTranscodeTargetBitrateKbps].
  hd,
}

extension VideoSendQualityExt on VideoSendQuality {
  int get targetWidth => this == VideoSendQuality.hd ? 1280 : 854;

  int get targetHeight => this == VideoSendQuality.hd ? 720 : 480;

  int get targetBitrateKbps => this == VideoSendQuality.hd
      ? kVideoTranscodeTargetBitrateKbps
      : kVideoTranscodeSdBitrateKbps;
}

/// Stages surfaced to the UI while building [AppTimelineSendPrep] (before Matrix upload).
enum MediaOutboundPrepStage {
  /// H.264/AAC transcode for large videos (before thumbnail).
  compressingVideo,

  /// JPEG thumbnail via `media` (from compressed or source file).
  generatingThumbnail,
}

typedef MediaOutboundPrepStageCallback = void Function(MediaOutboundPrepStage stage);

/// Parallel [estimateCompression] results for 720p (HD) and 480p (SD) targets.
class VideoHdSdEstimates {
  const VideoHdSdEstimates({this.hd720Bytes, this.sd480Bytes});

  /// 1280×720 target.
  final int? hd720Bytes;

  /// 854×480 (16:9) target.
  final int? sd480Bytes;
}

int? _clampEstimatedBytesToSource(int estimated, int sourceLen) {
  if (estimated <= 0) return null;
  return estimated > sourceLen ? sourceLen : estimated;
}

int? _probeDurationMs(VideoProbe probe) {
  final d = probe.durationMs;
  if (d == null) return null;
  final ms = d.toInt();
  return ms > 0 ? ms : null;
}

/// Uses `media` [estimateCompressedSize] with [VideoPreset.p720] and [VideoPreset.p480]
/// (Telegram-style bitrate caps; close to prior 720p/480p targets).
/// Below [kVideoTranscodeMinBytes], both estimates are the source file size (no transcode).
Future<VideoHdSdEstimates> estimateVideoHdSdOutputBytesParallel(
  String sourcePath,
) async {
  final src = File(sourcePath);
  if (!await src.exists()) {
    return const VideoHdSdEstimates();
  }
  final sourceLen = await src.length();
  if (sourceLen < kVideoTranscodeMinBytes) {
    return VideoHdSdEstimates(
      hd720Bytes: sourceLen,
      sd480Bytes: sourceLen,
    );
  }

  try {
    await Media.init();
    final probe = await Media.probe(sourcePath);
    final hdEst = estimateCompressedSize(
      probe: probe,
      preset: VideoPreset.p720,
    );
    final sdEst = estimateCompressedSize(
      probe: probe,
      preset: VideoPreset.p480,
    );
    return VideoHdSdEstimates(
      hd720Bytes: _clampEstimatedBytesToSource(hdEst.estimatedBytes, sourceLen),
      sd480Bytes: _clampEstimatedBytesToSource(sdEst.estimatedBytes, sourceLen),
    );
  } catch (e, st) {
    developer.log(
      'estimateCompressedSize (media)',
      error: e,
      stackTrace: st,
      name: 'matrix.timeline_send',
    );
    return const VideoHdSdEstimates();
  }
}

/// Result of [`prepareVideoForTimelineSend`]; delete [filesToCleanup] after the Matrix send finishes.
class VideoSendMediaPrep {
  VideoSendMediaPrep({
    required this.filePathToSend,
    required this.appThumbnailJpegPath,
    required this.filesToCleanup,
  });

  final String filePathToSend;
  final String? appThumbnailJpegPath;
  final List<File> filesToCleanup;

  void dispose() {
    for (final f in filesToCleanup) {
      try {
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }
}

/// JPEG thumbnail from [`prepareRasterImageThumbnailForTimelineSend`]; delete [filesToCleanup] after send.
class ImageThumbnailPrep {
  ImageThumbnailPrep({required this.jpegPath, required this.filesToCleanup});

  final String jpegPath;
  final List<File> filesToCleanup;

  void dispose() {
    for (final f in filesToCleanup) {
      try {
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }
}

/// App-generated timeline thumbnail via the `media` package; pass [appThumbnailJpegPath] to Rust only
/// (Matrix SDK / homeserver are not used to synthesize image or video thumbs on send).
class AppTimelineSendPrep {
  AppTimelineSendPrep._({
    required this.filePathToSend,
    this.appThumbnailJpegPath,
    required List<File> filesToCleanup,
  }) : _filesToCleanup = List<File>.from(filesToCleanup);

  final String filePathToSend;
  final String? appThumbnailJpegPath;
  final List<File> _filesToCleanup;

  /// Runs [prepareVideoForTimelineSend] or [prepareRasterImageThumbnailForTimelineSend] when the file
  /// looks like video or raster image (extension, [mimeType], or magic bytes).
  static Future<AppTimelineSendPrep?> prepare(
    String path, {
    String? mimeType,
  }) async {
    return prepareForSend(path, mimeType: mimeType, onStage: null);
  }

  /// Like [prepare] but notifies [onStage] before compress / thumbnail work (for send UI).
  static Future<AppTimelineSendPrep?> prepareForSend(
    String path, {
    String? mimeType,
    MediaOutboundPrepStageCallback? onStage,
    VideoSendQuality videoQuality = VideoSendQuality.sd,
  }) async {
    final m = mimeType?.toLowerCase().trim();
    if (m != null && m.startsWith('video/')) {
      return _fromVideo(path, onStage: onStage, quality: videoQuality);
    }
    if (m != null && m.startsWith('image/')) {
      return _fromImage(path, onStage: onStage);
    }
    if (m != null && m.startsWith('audio/')) {
      return null;
    }
    if (isProbableAudioFilePath(path)) {
      return null;
    }
    if (await isTimelineVideoSendCandidate(path, mimeType: mimeType)) {
      return _fromVideo(path, onStage: onStage, quality: videoQuality);
    }
    if (await isTimelineImageSendCandidate(path, mimeType: mimeType)) {
      return _fromImage(path, onStage: onStage);
    }
    return null;
  }

  static Future<AppTimelineSendPrep?> _fromVideo(
    String path, {
    MediaOutboundPrepStageCallback? onStage,
    VideoSendQuality quality = VideoSendQuality.sd,
  }) async {
    final v = await prepareVideoForTimelineSend(
      path,
      onStage: onStage,
      quality: quality,
    );
    if (v == null) return null;
    return AppTimelineSendPrep._(
      filePathToSend: v.filePathToSend,
      appThumbnailJpegPath: v.appThumbnailJpegPath,
      filesToCleanup: v.filesToCleanup,
    );
  }

  static Future<AppTimelineSendPrep> _fromImage(
    String path, {
    MediaOutboundPrepStageCallback? onStage,
  }) async {
    onStage?.call(MediaOutboundPrepStage.generatingThumbnail);
    final thumb = await prepareRasterImageThumbnailForTimelineSend(path);
    return AppTimelineSendPrep._(
      filePathToSend: path,
      appThumbnailJpegPath: thumb?.jpegPath,
      filesToCleanup: thumb?.filesToCleanup ?? <File>[],
    );
  }

  void dispose() {
    for (final f in _filesToCleanup) {
      try {
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }
}

bool isProbableVideoFilePath(String path) {
  const exts = {
    'mp4',
    'mov',
    'webm',
    'mkv',
    'm4v',
    'avi',
    'mpeg',
    'mpg',
    '3gp',
  };
  final e = p.extension(path.toLowerCase()).replaceFirst('.', '');
  return exts.contains(e);
}

/// Voice / music containers (often ISO BMFF like `.m4a` — must not use the video thumbnail pipeline).
bool isProbableAudioFilePath(String path) {
  const exts = {
    'm4a',
    'aac',
    'mp3',
    'ogg',
    'oga',
    'opus',
    'wav',
    'flac',
    'caf',
  };
  final e = p.extension(path.toLowerCase()).replaceFirst('.', '');
  return exts.contains(e);
}

/// True when we should run [prepareVideoForTimelineSend] so Rust gets a JPEG for `thumbnail_url`.
///
/// Gallery picks often use names like `image_picker_…` with **no extension**; extension-only checks
/// miss those and the Matrix event is sent **without** `info.thumbnail_url`, so the timeline falls
/// back to thumbnailing the main video MXC (often MP4/MOV bytes, not a raster).
///
/// **Not** for audio: `.m4a` / `audio/mp4` share ISO BMFF `ftyp` with MP4, so we exclude `audio/*`
/// and known audio extensions before [fileHeaderLooksLikeVideoContainer].
Future<bool> isTimelineVideoSendCandidate(
  String path, {
  String? mimeType,
}) async {
  final m = mimeType?.toLowerCase().trim();
  if (m != null && m.startsWith('audio/')) return false;
  if (isProbableAudioFilePath(path)) return false;
  if (m != null && m.startsWith('video/')) return true;
  if (isProbableVideoFilePath(path)) return true;
  return fileHeaderLooksLikeVideoContainer(path);
}

/// ISO BMFF video (`ftyp` + non-still-image brand), RIFF, or EBML — not HEIF/HEIC (also BMFF).
Future<bool> fileHeaderLooksLikeVideoContainer(String path) async {
  final f = File(path);
  if (!await f.exists()) return false;
  RandomAccessFile? raf;
  try {
    raf = await f.open();
    final buf = await raf.read(12);
    if (buf.length < 12) return false;
    if (buf[4] == 0x66 &&
        buf[5] == 0x74 &&
        buf[6] == 0x79 &&
        buf[7] == 0x70) {
      final brand =
          String.fromCharCodes(buf.sublist(8, 12)).toLowerCase().trim();
      if (_isIsoBmffStillImageBrand(brand)) {
        return false;
      }
      return true;
    }
    if (buf[0] == 0x52 &&
        buf[1] == 0x49 &&
        buf[2] == 0x46 &&
        buf[3] == 0x46) {
      return true;
    }
    // WebM / Matroska (EBML)
    if (buf[0] == 0x1a &&
        buf[1] == 0x45 &&
        buf[2] == 0xdf &&
        buf[3] == 0xa3) {
      return true;
    }
    return false;
  } catch (_) {
    return false;
  } finally {
    await raf?.close();
  }
}

bool _isIsoBmffStillImageBrand(String brand) {
  if (brand.isEmpty) return false;
  const prefixes = ['heic', 'heif', 'heix', 'heim', 'heis', 'mif1', 'msf1', 'avif', 'miaf'];
  for (final p in prefixes) {
    if (brand.startsWith(p)) return true;
  }
  return false;
}

/// JPEG / PNG / GIF / WebP / BMP, or ISO BMFF still image (HEIC/AVIF).
Future<bool> fileHeaderLooksLikeRasterImage(String path) async {
  final f = File(path);
  if (!await f.exists()) return false;
  RandomAccessFile? raf;
  try {
    raf = await f.open();
    final buf = await raf.read(16);
    if (buf.length < 3) return false;
    if (buf[0] == 0xff && buf[1] == 0xd8 && buf[2] == 0xff) return true;
    if (buf.length >= 8 &&
        buf[0] == 0x89 &&
        buf[1] == 0x50 &&
        buf[2] == 0x4e &&
        buf[3] == 0x47 &&
        buf[4] == 0x0d &&
        buf[5] == 0x0a &&
        buf[6] == 0x1a &&
        buf[7] == 0x0a) {
      return true;
    }
    if (buf.length >= 6) {
      final g = String.fromCharCodes(buf.sublist(0, 6));
      if (g == 'GIF87a' || g == 'GIF89a') return true;
    }
    if (buf.length >= 12 &&
        buf[0] == 0x52 &&
        buf[1] == 0x49 &&
        buf[2] == 0x46 &&
        buf[3] == 0x46 &&
        buf[8] == 0x57 &&
        buf[9] == 0x45 &&
        buf[10] == 0x42 &&
        buf[11] == 0x50) {
      return true;
    }
    if (buf.length >= 2 && buf[0] == 0x42 && buf[1] == 0x4d) return true;
    if (buf.length >= 12 &&
        buf[4] == 0x66 &&
        buf[5] == 0x74 &&
        buf[6] == 0x79 &&
        buf[7] == 0x70) {
      final brand =
          String.fromCharCodes(buf.sublist(8, 12)).toLowerCase().trim();
      return _isIsoBmffStillImageBrand(brand);
    }
    return false;
  } catch (_) {
    return false;
  } finally {
    await raf?.close();
  }
}

Future<bool> isTimelineImageSendCandidate(
  String path, {
  String? mimeType,
}) async {
  final m = mimeType?.toLowerCase().trim();
  if (m != null && m.startsWith('image/')) return true;
  if (isProbableRasterImageFilePath(path)) return true;
  return fileHeaderLooksLikeRasterImage(path);
}

bool isProbableRasterImageFilePath(String path) {
  const exts = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic', 'heif'};
  final e = p.extension(path.toLowerCase()).replaceFirst('.', '');
  return exts.contains(e);
}

/// Uses the `media` package to emit a JPEG suitable for Matrix `info` / thumbnail upload.
Future<ImageThumbnailPrep?> prepareRasterImageThumbnailForTimelineSend(
  String sourcePath,
) async {
  final src = File(sourcePath);
  if (!await src.exists()) return null;

  final dir = await getTemporaryDirectory();
  final base = p.basename(sourcePath);
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final thumbOut = p.join(dir.path, 'matrix_img_thumb_${stamp}_$base.jpg');

  try {
    await Media.init();
    final writtenPath = await Media.thumbnailSaveToPath(
      path: sourcePath,
      outputPath: thumbOut,
      timeSec: 0,
      maxEdge: 720,
      format: ThumbnailFormat.jpeg,
    );
    final tf = File(writtenPath);
    if (await tf.exists() && await tf.length() > 0) {
      return ImageThumbnailPrep(jpegPath: writtenPath, filesToCleanup: [tf]);
    }
  } catch (_) {}

  return null;
}

/// Uses `media` [Media.transcodeVideoStream] then [Media.thumbnailSaveToPath] on the file we upload.
///
/// Single JPEG frame for send UI preview via [Media.thumbnailSaveToPath].
/// Caller should delete the file when done.
Future<String?> generateVideoPreviewThumbnailForUi(String sourcePath) async {
  final src = File(sourcePath);
  if (!await src.exists()) return null;
  final dir = await getTemporaryDirectory();
  final base = p.basename(sourcePath);
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final thumbOut = p.join(dir.path, 'matrix_preview_thumb_${stamp}_$base.jpg');
  try {
    await Media.init();
    final writtenPath = await Media.thumbnailSaveToPath(
      path: sourcePath,
      outputPath: thumbOut,
      timeSec: 1.0,
      maxEdge: 720,
      format: ThumbnailFormat.jpeg,
    );
    final tf = File(writtenPath);
    if (await tf.exists() && await tf.length() > 0) {
      return writtenPath;
    }
  } catch (e, st) {
    developer.log(
      'preview thumbnail',
      error: e,
      stackTrace: st,
      name: 'matrix.timeline_send',
    );
  }
  return null;
}

Future<VideoSendMediaPrep?> prepareVideoForTimelineSend(
  String sourcePath, {
  MediaOutboundPrepStageCallback? onStage,
  VideoSendQuality quality = VideoSendQuality.sd,
}) async {
  final src = File(sourcePath);
  if (!await src.exists()) return null;

  final temps = <File>[];
  final dir = await getTemporaryDirectory();
  final base = p.basename(sourcePath);
  final stamp = DateTime.now().microsecondsSinceEpoch;

  var pathToSend = sourcePath;
  final len = await src.length();
  if (len >= kVideoTranscodeMinBytes) {
    onStage?.call(MediaOutboundPrepStage.compressingVideo);
    try {
      await Media.init();
      final outBase = p.join(dir.path, 'matrix_media_vid_${stamp}_$base');
      final outMp4 = outBase.toLowerCase().endsWith('.mp4')
          ? outBase
          : '$outBase.mp4';
      await for (final _ in Media.transcodeVideoStream(
        inputPath: sourcePath,
        outputPath: outMp4,
        videoBitrateKbps: quality.targetBitrateKbps,
        maxWidth: quality.targetWidth,
        audioBitrateKbps: 128,
      )) {}
      final out = File(outMp4);
      if (await out.exists()) {
        final outLen = await out.length();
        if (outLen > 0 && outLen + 65536 < len) {
          pathToSend = outMp4;
          temps.add(out);
        } else {
          try {
            await out.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  onStage?.call(MediaOutboundPrepStage.generatingThumbnail);

  final timeCandidatesSec = <double>[
    1.0,
    0.0,
    0.5,
    0.25,
    2.0,
    0.1,
    3.0,
  ];
  try {
    await Media.init();
    final info = await Media.probe(pathToSend);
    final durMs = _probeDurationMs(info);
    if (durMs != null) {
      final midSec = durMs / 2000.0;
      if (midSec > 0) {
        timeCandidatesSec.insert(0, midSec);
      }
    }
  } catch (_) {}

  String? thumbPath;
  final seenTimes = <String>{};
  for (final timeSec in timeCandidatesSec) {
    final key = timeSec.toString();
    if (!seenTimes.add(key)) continue;
    final thumbOut =
        p.join(dir.path, 'matrix_media_thumb_${stamp}_${key}_$base.jpg');
    try {
      await Media.init();
      final writtenPath = await Media.thumbnailSaveToPath(
        path: pathToSend,
        outputPath: thumbOut,
        timeSec: timeSec,
        maxEdge: 720,
        format: ThumbnailFormat.jpeg,
      );
      final tf = File(writtenPath);
      if (await tf.exists() && await tf.length() > 0) {
        thumbPath = writtenPath;
        temps.add(tf);
        break;
      }
    } catch (e, st) {
      developer.log(
        'Video thumbnail (media package) t=$timeSec s',
        error: e,
        stackTrace: st,
        name: 'matrix.timeline_send',
      );
    }
  }

  if (thumbPath == null) {
    final thumbOut =
        p.join(dir.path, 'matrix_media_thumb_${stamp}_fallback_$base.jpg');
    try {
      await Media.init();
      final writtenPath = await Media.thumbnailSaveToPath(
        path: pathToSend,
        outputPath: thumbOut,
        timeSec: 1.0,
        maxEdge: 512,
        format: ThumbnailFormat.jpeg,
      );
      final tf = File(writtenPath);
      if (await tf.exists() && await tf.length() > 0) {
        thumbPath = writtenPath;
        temps.add(tf);
      }
    } catch (e, st) {
      developer.log(
        'Video thumbnail fallback',
        error: e,
        stackTrace: st,
        name: 'matrix.timeline_send',
      );
    }
  }

  if (thumbPath == null) {
    for (final f in temps) {
      try {
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    return null;
  }

  return VideoSendMediaPrep(
    filePathToSend: pathToSend,
    appThumbnailJpegPath: thumbPath,
    filesToCleanup: temps,
  );
}
