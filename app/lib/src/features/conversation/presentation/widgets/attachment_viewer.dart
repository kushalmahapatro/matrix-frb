import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:matrix/src/core/matrix_media_kit_video.dart';
import 'package:matrix_sdk/matrix_sdk.dart'
    show RoomMessageKind, documentPreviewJson;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';

/// In-app attachment viewers. Bytes come from Rust ([MatrixClient.fetchRoomMessageMedia]).
///
/// Office files use Rust-side extraction (`documentPreviewJson`): calamine for spreadsheets,
/// zip/XML for Word/PowerPoint/OpenDocument, pdf-extract when the native PDF engine is missing.
/// [OpenFilex] is only for unknown types or when extraction fails.
class AttachmentViewer {
  AttachmentViewer._();

  static String _extensionOf(String name) {
    final base = p.basename(name.trim());
    final dot = base.lastIndexOf('.');
    if (dot < 0 || dot == base.length - 1) return '';
    return base.substring(dot + 1).toLowerCase();
  }

  static bool _isImageExt(String ext) =>
      const {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'}.contains(ext);

  static bool _isVideoExt(String ext) =>
      const {'mp4', 'mov', 'webm', 'mkv', 'm4v', 'avi'}.contains(ext);

  static bool _isAudioExt(String ext) =>
      const {'mp3', 'm4a', 'aac', 'ogg', 'opus', 'flac', 'wav'}.contains(ext);

  /// Plain text in Flutter (UTF-8). CSV is handled via Rust for a table preview.
  static bool _isTextExt(String ext) => const {
    'txt',
    'md',
    'json',
    'xml',
    'log',
    'dart',
    'rs',
    'kt',
    'swift',
    'html',
    'css',
    'scss',
    'yaml',
    'yml',
    'sh',
    'env',
    'gitignore',
  }.contains(ext);

  /// Structured preview via [documentPreviewJson] (Rust).
  static bool _isRustStructuredExt(String ext) => const {
    'csv',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'xlsm',
    'xlsb',
    'ppt',
    'pptx',
    'odt',
    'ods',
    'odp',
    'rtf',
  }.contains(ext);

  static _ViewerKind _classify(String filename, RoomMessageKind kind) {
    final ext = _extensionOf(filename);
    switch (kind) {
      case RoomMessageKind.image:
        return _ViewerKind.image;
      case RoomMessageKind.video:
        return _ViewerKind.video;
      case RoomMessageKind.audio:
        return _ViewerKind.audio;
      case RoomMessageKind.file:
        if (_isImageExt(ext) || ext == 'heic' || ext == 'heif') {
          return _ViewerKind.image;
        }
        if (_isVideoExt(ext)) return _ViewerKind.video;
        if (_isAudioExt(ext)) return _ViewerKind.audio;
        if (ext == 'pdf') return _ViewerKind.pdf;
        if (_isRustStructuredExt(ext)) return _ViewerKind.rustDocument;
        if (_isTextExt(ext)) return _ViewerKind.text;
        return _ViewerKind.unknown;
      case RoomMessageKind.text:
      case RoomMessageKind.poll:
      case RoomMessageKind.other:
        return _ViewerKind.unknown;
    }
  }

  static Future<File> _writeTemp(Uint8List bytes, String filename) async {
    final dir = await getTemporaryDirectory();
    final safe = p
        .basename(filename)
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final f = File(
      '${dir.path}/matrix_view_${DateTime.now().millisecondsSinceEpoch}_$safe',
    );
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  static Future<void> openExternally(Uint8List bytes, String filename) async {
    final f = await _writeTemp(bytes, filename);
    await OpenFilex.open(f.path);
  }

  static Future<void> _openRustDocumentPreview(
    BuildContext context, {
    required String label,
    required Uint8List data,
    String? forceExtension,
  }) async {
    final ext = forceExtension ?? _extensionOf(label);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const PopScope(
        canPop: false,
        child: Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Preparing preview…'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    late final String jsonStr;
    try {
      jsonStr = await documentPreviewJson(extension_: ext, data: data);
    } finally {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    if (!context.mounted) return;

    final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
    if (decoded['ok'] != true) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _LastResortPreviewPage(
            title: label,
            bytes: data,
            message: decoded['error']?.toString() ?? 'Preview failed.',
          ),
        ),
      );
      return;
    }

    final preview = decoded['preview'] as Map<String, dynamic>?;
    if (preview == null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _LastResortPreviewPage(
            title: label,
            bytes: data,
            message: 'Invalid preview payload.',
          ),
        ),
      );
      return;
    }

    final kind = preview['kind'] as String?;
    switch (kind) {
      case 'text':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _StructuredTextDocumentPage(
              title: label,
              body: preview['body'] as String? ?? '',
              note: preview['note'] as String? ?? '',
              bytes: data,
            ),
          ),
        );
        break;
      case 'sheet':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _SheetPreviewPage(
              title: label,
              sheetName: preview['sheet'] as String? ?? '',
              rows: (preview['rows'] as List<dynamic>? ?? [])
                  .map(
                    (r) =>
                        (r as List<dynamic>).map((c) => c.toString()).toList(),
                  )
                  .toList(),
              truncated: preview['truncated'] == true,
              note: preview['note'] as String? ?? '',
              bytes: data,
            ),
          ),
        );
        break;
      case 'slides':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _SlidesPreviewPage(
              title: label,
              slides: (preview['slides'] as List<dynamic>? ?? [])
                  .map((e) => e.toString())
                  .toList(),
              note: preview['note'] as String? ?? '',
              bytes: data,
            ),
          ),
        );
        break;
      default:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _LastResortPreviewPage(
              title: label,
              bytes: data,
              message: 'Unsupported preview type.',
            ),
          ),
        );
    }
  }

  /// Loads full media (not thumbnail) and pushes a viewer.
  static Future<void> open(
    BuildContext context, {
    required Future<Uint8List?> Function() loadFullBytes,
    required String filename,
    required RoomMessageKind roomMsgKind,
    String? mediaMimetype,
  }) async {
    if (!context.mounted) return;

    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Attachment viewer is not available on web.'),
        ),
      );
      return;
    }

    final label = filename.trim().isEmpty ? 'attachment' : filename.trim();
    final kind = _classify(label, roomMsgKind);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const PopScope(
        canPop: false,
        child: Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading…'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    Uint8List? bytes;
    try {
      bytes = await loadFullBytes();
    } finally {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    if (!context.mounted) return;
    if (bytes == null || bytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load attachment.')),
      );
      return;
    }

    final data = bytes;

    switch (kind) {
      case _ViewerKind.image:
        if (!context.mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _ImageViewerPage(title: label, bytes: data),
          ),
        );
      case _ViewerKind.video:
        if (!context.mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _VideoViewerPage(title: label, bytes: data),
          ),
        );
      case _ViewerKind.audio:
        if (!context.mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _AudioViewerPage(
              title: label,
              bytes: data,
              mimeHint: mediaMimetype,
            ),
          ),
        );
      case _ViewerKind.pdf:
        final supported = await hasPdfSupport();
        if (!context.mounted) return;
        if (supported) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => _PdfViewerPage(title: label, bytes: data),
            ),
          );
        } else {
          await _openRustDocumentPreview(
            context,
            label: label,
            data: data,
            forceExtension: 'pdf',
          );
        }
      case _ViewerKind.rustDocument:
        if (!context.mounted) return;
        await _openRustDocumentPreview(context, label: label, data: data);
      case _ViewerKind.text:
        if (!context.mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _TextViewerPage(title: label, bytes: data),
          ),
        );
      case _ViewerKind.unknown:
        if (!context.mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _LastResortPreviewPage(
              title: label,
              bytes: data,
              message:
                  'No built-in preview for this file type. You can open it with another app.',
            ),
          ),
        );
    }
  }
}

enum _ViewerKind { image, video, audio, pdf, rustDocument, text, unknown }

List<Widget> _systemOpenMenuActions(Uint8List bytes, String title) => [
  PopupMenuButton<void>(
    icon: const Icon(Icons.more_vert),
    tooltip: 'More',
    itemBuilder: (context) => [
      PopupMenuItem<void>(
        onTap: () => Future<void>.microtask(
          () => AttachmentViewer.openExternally(bytes, title),
        ),
        child: const Text('Open with system app'),
      ),
    ],
  ),
];

class _LastResortPreviewPage extends StatelessWidget {
  const _LastResortPreviewPage({
    required this.title,
    required this.bytes,
    required this.message,
  });

  final String title;
  final Uint8List bytes;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: _systemOpenMenuActions(bytes, title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.insert_drive_file_outlined,
              size: 56,
              color: theme.colorScheme.tertiary,
            ),
            const SizedBox(height: 16),
            Text(message, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => AttachmentViewer.openExternally(bytes, title),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open with system app'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Extracted text with paragraph spacing + a second tab to open the binary in a system viewer
/// (true WYSIWYG for Word/PowerPoint is not available without embedding a full office engine).
class _StructuredTextDocumentPage extends StatelessWidget {
  const _StructuredTextDocumentPage({
    required this.title,
    required this.body,
    required this.note,
    required this.bytes,
  });

  final String title;
  final String body;
  final String note;
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: _systemOpenMenuActions(bytes, title),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Preview'),
              Tab(text: 'Original'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _FormattedExtractedTextTab(note: note, body: body),
            _OriginalFileOpenTab(title: title, bytes: bytes),
          ],
        ),
      ),
    );
  }
}

class _FormattedExtractedTextTab extends StatelessWidget {
  const _FormattedExtractedTextTab({required this.note, required this.body});

  final String note;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trimmed = body.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (note.isNotEmpty)
          Material(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(note, style: theme.textTheme.bodySmall),
            ),
          ),
        Expanded(
          child: trimmed.isEmpty
              ? Center(
                  child: Text(
                    'No text to show.',
                    style: theme.textTheme.bodyMedium,
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: SelectableText(
                    body,
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                  ),
                ),
        ),
      ],
    );
  }
}

class _OriginalFileOpenTab extends StatelessWidget {
  const _OriginalFileOpenTab({required this.title, required this.bytes});

  final String title;
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.description_outlined,
            size: 56,
            color: theme.colorScheme.tertiary,
          ),
          const SizedBox(height: 16),
          Text(
            'Original layout, fonts, and embedded media are only available in a full office or PDF app.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Use “Open with system app” to view or edit the file with Quick Look, Word, Keynote, etc.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: () => AttachmentViewer.openExternally(bytes, title),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open with system app'),
          ),
        ],
      ),
    );
  }
}

class _SheetPreviewPage extends StatelessWidget {
  const _SheetPreviewPage({
    required this.title,
    required this.sheetName,
    required this.rows,
    required this.truncated,
    required this.note,
    required this.bytes,
  });

  final String title;
  final String sheetName;
  final List<List<String>> rows;
  final bool truncated;
  final String note;
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    var colCount = 0;
    for (final r in rows) {
      if (r.length > colCount) colCount = r.length;
    }
    colCount = colCount.clamp(1, 64);

    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: _systemOpenMenuActions(bytes, title),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (note.isNotEmpty || sheetName.isNotEmpty || truncated)
            Material(
              color: theme.colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  [
                    if (sheetName.isNotEmpty) 'Sheet: $sheetName',
                    if (truncated) 'Rows/columns may be truncated.',
                    if (note.isNotEmpty) note,
                  ].join('\n'),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: Text('No rows', style: theme.textTheme.bodyMedium),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minWidth: constraints.maxWidth,
                            ),
                            child: DataTable(
                              headingRowHeight: 40,
                              dataRowMinHeight: 44,
                              dataRowMaxHeight: 120,
                              columnSpacing: 20,
                              horizontalMargin: 12,
                              columns: List.generate(
                                colCount,
                                (i) => DataColumn(
                                  label: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 200,
                                    ),
                                    child: Text(
                                      '${i + 1}',
                                      style: theme.textTheme.labelSmall,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ),
                              rows: rows
                                  .map(
                                    (r) => DataRow(
                                      cells: List.generate(
                                        colCount,
                                        (i) => DataCell(
                                          ConstrainedBox(
                                            constraints: const BoxConstraints(
                                              maxWidth: 220,
                                            ),
                                            child: SelectableText(
                                              i < r.length ? r[i] : '',
                                              maxLines: 6,
                                              style: theme.textTheme.bodySmall,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SlidesPreviewPage extends StatelessWidget {
  const _SlidesPreviewPage({
    required this.title,
    required this.slides,
    required this.note,
    required this.bytes,
  });

  final String title;
  final List<String> slides;
  final String note;
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: _systemOpenMenuActions(bytes, title),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Slide text'),
              Tab(text: 'Original'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (note.isNotEmpty)
                  Material(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(note, style: theme.textTheme.bodySmall),
                    ),
                  ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 12,
                    ),
                    itemCount: slides.length,
                    separatorBuilder: (_, __) => const Divider(height: 28),
                    itemBuilder: (context, i) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(radius: 18, child: Text('${i + 1}')),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SelectableText(
                                slides[i],
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  height: 1.45,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            _OriginalFileOpenTab(title: title, bytes: bytes),
          ],
        ),
      ),
    );
  }
}

class _ImageViewerPage extends StatelessWidget {
  const _ImageViewerPage({required this.title, required this.bytes});

  final String title;
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        foregroundColor: theme.colorScheme.primary,
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: _systemOpenMenuActions(bytes, title),
      ),
      body: PhotoView(
        imageProvider: MemoryImage(bytes),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 4,
        backgroundDecoration: const BoxDecoration(color: Colors.black),
      ),
    );
  }
}

class _VideoViewerPage extends StatefulWidget {
  const _VideoViewerPage({required this.title, required this.bytes});

  final String title;
  final Uint8List bytes;

  @override
  State<_VideoViewerPage> createState() => _VideoViewerPageState();
}

class _VideoViewerPageState extends State<_VideoViewerPage> {
  late final Player _player = Player();
  late final VideoController _videoController = VideoController(
    _player,
    configuration: matrixPlaybackVideoControllerConfiguration(),
  );
  bool _ready = false;
  String? _error;
  File? _tempVideoFile;

  @override
  void initState() {
    super.initState();
    _init();
  }

  /// Real extension helps libav detect format (`Media.memory` is unreliable on iOS).
  static String _videoTempSuffix(String title) {
    final base = p.basename(title.trim().toLowerCase());
    final dot = base.lastIndexOf('.');
    if (dot > 0 && dot < base.length - 1) {
      final ext = base.substring(dot);
      if (ext.length <= 10 && RegExp(r'^[.][a-z0-9]+$').hasMatch(ext)) {
        return ext;
      }
    }
    return '.mp4';
  }

  Future<void> _init() async {
    try {
      if (!matrixBytesLookLikeVideoContainer(widget.bytes)) {
        if (mounted) {
          setState(
            () => _error =
                'This file does not look like a supported video format.',
          );
        }
        return;
      }
      final dir = await getTemporaryDirectory();
      final suffix = _videoTempSuffix(widget.title);
      final f = File(
        '${dir.path}/matrix_view_vid_${DateTime.now().microsecondsSinceEpoch}$suffix',
      );
      await f.writeAsBytes(widget.bytes, flush: true);
      _tempVideoFile = f;
      await matrixAwaitVideoControllerPlatformReady(_videoController);
      final uri = Uri.file(f.path);
      await _player.open(Media(uri.toString()));
      if (!mounted) return;
      setState(() => _ready = true);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      await _player.play();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    try {
      _player.dispose();
    } finally {
      final t = _tempVideoFile;
      if (t != null) {
        try {
          if (t.existsSync()) t.deleteSync();
        } catch (_) {}
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: _systemOpenMenuActions(widget.bytes, widget.title),
      ),
      body: Center(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'If playback fails (codec or container), open the file with the system video player.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => AttachmentViewer.openExternally(
                        widget.bytes,
                        widget.title,
                      ),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Open with system app'),
                    ),
                  ],
                ),
              )
            : !_ready
            ? const CircularProgressIndicator()
            : SafeArea(
                child: Video(
                  controller: _videoController,
                  controls: AdaptiveVideoControls,
                ),
              ),
      ),
    );
  }
}

class _AudioViewerPage extends StatefulWidget {
  const _AudioViewerPage({
    required this.title,
    required this.bytes,
    this.mimeHint,
  });

  final String title;
  final Uint8List bytes;
  final String? mimeHint;

  @override
  State<_AudioViewerPage> createState() => _AudioViewerPageState();
}

class _AudioViewerPageState extends State<_AudioViewerPage> {
  late final ja.AudioPlayer _player = ja.AudioPlayer();
  bool _opened = false;
  String? _error;
  File? _tempAudioFile;

  @override
  void initState() {
    super.initState();
    _open();
  }

  /// Real extension + temp path so platform decoders recognize AAC/M4A.
  static String _audioTempSuffix(String title, String? mime) {
    final ext = AttachmentViewer._extensionOf(title);
    if (ext.isNotEmpty && AttachmentViewer._isAudioExt(ext)) {
      return '.$ext';
    }
    final m = mime?.toLowerCase().trim() ?? '';
    if (m.contains('mpeg') || m.endsWith('/mp3')) return '.mp3';
    if (m.contains('mp4') || m.contains('m4a') || m.contains('x-m4a')) {
      return '.m4a';
    }
    if (m.contains('aac')) return '.aac';
    if (m.contains('ogg') || m.contains('opus')) return '.ogg';
    if (m.contains('flac')) return '.flac';
    if (m.contains('wav') || m.contains('wave')) return '.wav';
    return '.m4a';
  }

  Future<void> _open() async {
    try {
      final dir = await getTemporaryDirectory();
      final suffix = _audioTempSuffix(widget.title, widget.mimeHint);
      final f = File(
        '${dir.path}/matrix_view_aud_${DateTime.now().microsecondsSinceEpoch}$suffix',
      );
      await f.writeAsBytes(widget.bytes, flush: true);
      _tempAudioFile = f;
      await _player.setFilePath(f.path);
      if (mounted) setState(() => _opened = true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    final t = _tempAudioFile;
    if (t != null) {
      try {
        if (t.existsSync()) t.deleteSync();
      } catch (_) {}
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: _systemOpenMenuActions(widget.bytes, widget.title),
      ),
      body: Center(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              )
            : !_opened
            ? const CircularProgressIndicator()
            : StreamBuilder<ja.PlayerState>(
                stream: _player.playerStateStream,
                initialData: _player.playerState,
                builder: (context, snap) {
                  final playing = snap.data?.playing ?? false;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.audiotrack,
                        size: 72,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 24),
                      IconButton(
                        iconSize: 64,
                        icon: Icon(
                          playing ? Icons.pause_circle : Icons.play_circle,
                          color: theme.colorScheme.primary,
                        ),
                        onPressed: () async {
                          if (playing) {
                            await _player.pause();
                          } else {
                            await _player.play();
                          }
                        },
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

class _PdfViewerPage extends StatefulWidget {
  const _PdfViewerPage({required this.title, required this.bytes});

  final String title;
  final Uint8List bytes;

  @override
  State<_PdfViewerPage> createState() => _PdfViewerPageState();
}

class _PdfViewerPageState extends State<_PdfViewerPage> {
  PdfControllerPinch? _controller;

  @override
  void initState() {
    super.initState();
    _controller = PdfControllerPinch(
      document: PdfDocument.openData(widget.bytes),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = _controller;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: _systemOpenMenuActions(widget.bytes, widget.title),
      ),
      body: c == null
          ? const Center(child: CircularProgressIndicator())
          : PdfViewPinch(
              controller: c,
              backgroundDecoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
              ),
            ),
    );
  }
}

class _TextViewerPage extends StatelessWidget {
  const _TextViewerPage({required this.title, required this.bytes});

  final String title;
  final Uint8List bytes;

  static String? _monoFontForPath(String path) {
    final ext = p.extension(path.toLowerCase());
    const codeLike = {
      '.dart',
      '.rs',
      '.kt',
      '.kts',
      '.swift',
      '.json',
      '.yaml',
      '.yml',
      '.xml',
      '.html',
      '.css',
      '.scss',
      '.sh',
      '.env',
      '.gitignore',
      '.log',
    };
    if (codeLike.contains(ext)) return 'JetBrainsMono';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = utf8.decode(bytes, allowMalformed: true);
    final ext = p.extension(title.toLowerCase());
    final isMarkdown = ext == '.md';

    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied to clipboard')),
                );
              }
            },
          ),
          ..._systemOpenMenuActions(bytes, title),
        ],
      ),
      body: isMarkdown
          ? Markdown(
              data: text,
              selectable: true,
              padding: const EdgeInsets.all(16),
              styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                p: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                code: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: 'JetBrainsMono',
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                text,
                style: theme.textTheme.bodyLarge?.copyWith(
                  height: 1.45,
                  fontFamily: _monoFontForPath(title),
                ),
              ),
            ),
    );
  }
}
