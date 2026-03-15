import 'dart:developer' as developer;

import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

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
  // Build environment variables map
  final envVars = <String, String>{};

  final rustBuilder = RustBuilder(
    assetName: assetName,
    cratePath: 'rust',
    buildMode: BuildMode.release,
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
}
