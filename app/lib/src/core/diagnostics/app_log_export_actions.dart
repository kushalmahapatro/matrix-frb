import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:matrix/src/core/desktop/desktop_ui_helpers.dart';
import 'package:matrix/src/core/diagnostics/app_log_archive.dart';
import 'package:share_plus/share_plus.dart';

/// Share or save the Rust rolling-file log ZIP (UI + platform dialogs).
class AppLogExportActions {
  AppLogExportActions._();

  static Future<void> shareLogs(BuildContext context) async {
    if (kIsWeb) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      const SnackBar(content: Text('Preparing log archive…')),
    );
    try {
      final zip = await AppLogArchive.createZipInTemp();
      if (!context.mounted) return;
      messenger?.hideCurrentSnackBar();
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(zip.path, mimeType: 'application/zip')],
          subject: 'Matrix Terminal logs',
          text: 'Diagnostic log archive (Rust rolling file logs).',
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(
        SnackBar(content: Text('Could not share logs: $e')),
      );
    }
  }

  /// Desktop: native save dialog and copy ZIP. Mobile: [FilePicker] save with bytes.
  static Future<void> saveLogsToDisk(BuildContext context) async {
    if (kIsWeb) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      const SnackBar(content: Text('Preparing log archive…')),
    );
    try {
      final zip = await AppLogArchive.createZipInTemp();
      final bytes = await zip.readAsBytes();
      if (!context.mounted) return;
      messenger?.hideCurrentSnackBar();

      if (Platform.isAndroid || Platform.isIOS) {
        final path = await FilePicker.platform.saveFile(
          fileName: 'matrix-terminal-logs.zip',
          bytes: bytes,
          type: FileType.custom,
          allowedExtensions: const ['zip'],
        );
        if (!context.mounted) return;
        if (path != null) {
          messenger?.showSnackBar(SnackBar(content: Text('Saved to $path')));
        }
        return;
      }

      if (!isDesktopTargetPlatform()) return;

      var target = await FilePicker.platform.saveFile(
        dialogTitle: 'Save log archive',
        fileName: 'matrix-terminal-logs.zip',
        type: FileType.custom,
        allowedExtensions: const ['zip'],
      );
      if (!context.mounted) return;
      if (target == null) return;
      if (!target.toLowerCase().endsWith('.zip')) {
        target = '$target.zip';
      }
      await zip.copy(target);
      messenger?.showSnackBar(SnackBar(content: Text('Saved to $target')));
    } catch (e) {
      if (!context.mounted) return;
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(
        SnackBar(content: Text('Could not save logs: $e')),
      );
    }
  }
}
