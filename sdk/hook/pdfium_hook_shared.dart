import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Shared Pdfium download / extract for the build hook (host tree + per-target code assets).

Future<String?> pdfiumLatestReleaseTag() async {
  final client = HttpClient();
  try {
    final uri = Uri.parse(
      'https://api.github.com/repos/bblanchon/pdfium-binaries/releases/latest',
    );
    final req = await client.getUrl(uri);
    req.headers.set(HttpHeaders.userAgentHeader, 'matrix-sdk-native-hook');
    final res = await req.close();
    if (res.statusCode != HttpStatus.ok) return null;
    final body = await utf8.decoder.bind(res).join();
    final map = jsonDecode(body) as Map<String, Object?>;
    return map['tag_name'] as String?;
  } finally {
    client.close(force: true);
  }
}

bool pdfiumLibBasename(String name) {
  return name == 'libpdfium.dylib' ||
      name == 'libpdfium.so' ||
      name == 'pdfium.dll';
}

/// Downloads [archiveName] into [cacheTgz] if missing, extracts under [workRoot],
/// copies the primary Pdfium dynamic library into [outLibDir], returns that file.
Future<File?> pdfiumFetchExtractCopy({
  required String archiveName,
  required File cacheTgz,
  required Directory workRoot,
  required Directory outLibDir,
  void Function(String message)? log,
}) async {
  final tag = await pdfiumLatestReleaseTag();
  if (tag == null) {
    log?.call('matrix_sdk hook: Pdfium: could not read latest release tag');
    return null;
  }

  final encodedTag = tag.replaceAll('/', '%2F');
  final url =
      'https://github.com/bblanchon/pdfium-binaries/releases/download/$encodedTag/$archiveName';

  await cacheTgz.parent.create(recursive: true);
  if (!cacheTgz.existsSync()) {
    log?.call('matrix_sdk hook: Downloading Pdfium $archiveName …');
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader, 'matrix-sdk-native-hook');
      final res = await req.close();
      if (res.statusCode != HttpStatus.ok) {
        log?.call(
          'matrix_sdk hook: Pdfium download HTTP ${res.statusCode} for $url',
        );
        return null;
      }
      final sink = cacheTgz.openWrite();
      await res.pipe(sink);
      await sink.close();
    } finally {
      client.close(force: true);
    }
  }

  await outLibDir.create(recursive: true);
  final extractDir = Directory(p.join(workRoot.path, '_extract_$archiveName'));
  if (extractDir.existsSync()) {
    await extractDir.delete(recursive: true);
  }
  await extractDir.create(recursive: true);

  final tar = await Process.run('tar', [
    '-xzf',
    cacheTgz.path,
    '-C',
    extractDir.path,
  ]);
  if (tar.exitCode != 0) {
    log?.call('matrix_sdk hook: Pdfium: tar failed: ${tar.stderr}');
    return null;
  }

  File? found;
  await for (final e in extractDir.list(recursive: true, followLinks: false)) {
    if (e is! File) continue;
    if (pdfiumLibBasename(p.basename(e.path))) {
      found = e;
      break;
    }
  }

  if (found == null) {
    log?.call('matrix_sdk hook: Pdfium: no library in $archiveName');
    await extractDir.delete(recursive: true);
    return null;
  }

  final dest = File(p.join(outLibDir.path, p.basename(found.path)));
  await found.copy(dest.path);
  await extractDir.delete(recursive: true);
  log?.call('matrix_sdk hook: Pdfium library at ${dest.path}');
  return dest;
}
