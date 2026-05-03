import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:path/path.dart' as p;

import 'pdfium_hook_shared.dart';

/// bblanchon/pdfium-binaries archive for this [CodeConfig] target (Flutter native assets).
String? pdfiumArchiveNameForCodeTarget({
  required OS targetOS,
  required Architecture targetArch,
  IOSSdk? iosSdk,
}) {
  switch ((targetOS, targetArch)) {
    case (OS.android, Architecture.arm64):
      return 'pdfium-android-arm64.tgz';
    case (OS.android, Architecture.arm):
      return 'pdfium-android-arm.tgz';
    case (OS.android, Architecture.x64):
      return 'pdfium-android-x64.tgz';
    case (OS.android, Architecture.ia32):
      return 'pdfium-android-x86.tgz';
    case (OS.iOS, Architecture.arm64):
      if (iosSdk == IOSSdk.iPhoneSimulator) {
        return 'pdfium-ios-simulator-arm64.tgz';
      }
      if (iosSdk == IOSSdk.iPhoneOS) {
        return 'pdfium-ios-arm64.tgz';
      }
      return null;
    case (OS.iOS, Architecture.x64):
      return 'pdfium-ios-simulator-x64.tgz';
    case (OS.macOS, Architecture.arm64):
      return 'pdfium-mac-arm64.tgz';
    case (OS.macOS, Architecture.x64):
      return 'pdfium-mac-x64.tgz';
    case (OS.linux, Architecture.arm64):
      return 'pdfium-linux-arm64.tgz';
    case (OS.linux, Architecture.x64):
      return 'pdfium-linux-x64.tgz';
    case (OS.windows, Architecture.arm64):
      return 'pdfium-win-arm64.tgz';
    case (OS.windows, Architecture.x64):
      return 'pdfium-win-x64.tgz';
    default:
      return null;
  }
}

/// Registers Pdfium as an extra [CodeAsset] (same pipeline as [RustBuilder]’s library).
///
/// Uses [DynamicLoadingBundled] so the correct per-target `.so` / `.dylib` / `.dll`
/// is copied into the app bundle. Synthetic [name] is only used as an asset id.
Future<void> addPdfiumNativeCodeAsset({
  required BuildInput input,
  required BuildOutputBuilder output,
  void Function(String message)? log,
}) async {
  if (!input.config.buildCodeAssets) return;
  if (Platform.environment['MATRIX_HOOK_SKIP_NATIVE_MEDIA_BOOTSTRAP'] == '1') {
    return;
  }

  final code = input.config.code;
  final iosSdk = code.targetOS == OS.iOS ? code.iOS.targetSdk : null;
  final archive = pdfiumArchiveNameForCodeTarget(
    targetOS: code.targetOS,
    targetArch: code.targetArchitecture,
    iosSdk: iosSdk,
  );
  if (archive == null) {
    log?.call(
      'matrix_sdk hook: Pdfium code asset: unsupported target '
      '${code.targetOS} ${code.targetArchitecture}',
    );
    return;
  }

  final outHookDir = Directory.fromUri(input.outputDirectory);
  final workDir = Directory(p.join(outHookDir.path, 'pdfium_code_asset'));
  await workDir.create(recursive: true);

  final cacheDir = Directory(
    p.join(Directory.fromUri(input.packageRoot).path, '.matrix-sdk', 'cache'),
  );
  await cacheDir.create(recursive: true);
  final cacheTgz = File(p.join(cacheDir.path, archive));

  final libDir = Directory(p.join(workDir.path, 'lib'));
  try {
    final lib = await pdfiumFetchExtractCopy(
      archiveName: archive,
      cacheTgz: cacheTgz,
      workRoot: workDir,
      outLibDir: libDir,
      log: log,
    );
    if (lib == null) return;

    // Pdfium is always a dynamic library; Rust may use a different link mode.
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'native/pdfium_dl.dart',
        linkMode: DynamicLoadingBundled(),
        file: Uri.file(p.absolute(lib.path)),
      ),
    );
    log?.call(
      'matrix_sdk hook: Pdfium CodeAsset id package:${input.packageName}/native/pdfium_dl.dart',
    );
  } on Object catch (e) {
    log?.call('matrix_sdk hook: Pdfium CodeAsset failed (continuing): $e');
  }
}
