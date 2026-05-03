import 'dart:developer' as developer;

import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

import 'matrix_native_media_env.dart';
import 'native_media_bootstrap.dart';
import 'pdfium_code_asset.dart';

void main(List<String> args) async {
  await build(args, (BuildInput input, BuildOutputBuilder output) async {
    final String assetName = 'src/bindings/frb_generated.io.dart';
    await runLocalBuild(input, output, assetName);
  });
}

Future<void> runLocalBuild(
  BuildInput input,
  BuildOutputBuilder output,
  String assetName,
) async {
  await ensureMatrixNativeMediaArtifacts(
    packageRoot: input.packageRoot,
    log: (m) => developer.log(m, name: 'MatrixNativeMedia'),
  );

  // Pdfium / FFmpeg for `cargo`: env + `.matrix-sdk/native/` under this package.
  final envVars = {
    ...matrixNativeMediaCargoEnv(packageRoot: input.packageRoot),
    // Align with Runner IPHONEOS_DEPLOYMENT_TARGET; Cargo’s default (10.0) breaks
    // the final link (undefined ___chkstk_darwin) with modern Xcode + OpenSSL/SQLCipher.
    'IPHONEOS_DEPLOYMENT_TARGET': '13.0',
  };

  final rustBuilder = RustBuilder(
    assetName: assetName,
    cratePath: 'rust',
    buildMode: input.config.linkingEnabled
        ? BuildMode.release
        : BuildMode.debug,
    enableDefaultFeatures: true,
    extraCargoEnvironmentVariables: envVars,
  );

  final Logger logger = Logger.detached('MatrixSDKHookBuilder');
  logger.level = Level.CONFIG;
  logger.onRecord.listen(
    (LogRecord record) => developer.log(
      '${record.level.name}: ${record.time}: ${record.message}',
    ),
  );

  await rustBuilder.run(input: input, output: output, logger: logger);

  await addPdfiumNativeCodeAsset(
    input: input,
    output: output,
    log: (m) => developer.log(m, name: 'MatrixNativeMedia'),
  );
}
