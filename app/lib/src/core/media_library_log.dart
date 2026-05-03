import 'dart:async';

import 'package:matrix/src/core/logging_service.dart';
import 'package:media/media.dart';

/// Console / IDE filter for **`package:media` (media-rs)** lifecycle and major operations.
const String kMediaLibLogTag = 'MatrixMediaLib';

bool _mediaLibReadyLogged = false;

/// Calls [Media.init] and logs whether the native media library loaded.
///
/// On first success logs at **info**; in debug mode logs each [operation] at **debug**.
/// On failure logs **error** and rethrows (callers may catch, e.g. at app startup).
///
/// [timeout] avoids hanging forever when native init stalls (seen on some macOS
/// desktop runs); the underlying [Media.init] may still complete later.
Future<void> ensureMediaLibReady(
  String operation, {
  Duration? timeout,
}) async {
  try {
    Future<void> init = Media.init();
    if (timeout != null) {
      init = init.timeout(
        timeout,
        onTimeout: () => throw TimeoutException(
          'Media.init exceeded $timeout (op=$operation)',
          timeout,
        ),
      );
    }
    await init;
    if (!_mediaLibReadyLogged) {
      _mediaLibReadyLogged = true;
      LoggingService.info(
        kMediaLibLogTag,
        'package:media (media-rs): native library loaded — filter logs on "$kMediaLibLogTag"',
      );
    }
  } catch (e, st) {
    LoggingService.error(
      kMediaLibLogTag,
      'Media.init FAILED op=$operation error=$e',
    );
    Error.throwWithStackTrace(e, st);
  }
}
