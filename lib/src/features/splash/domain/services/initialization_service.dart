import 'dart:io';

import 'package:matrix/src/core/domain/services/app_config.dart';
import 'package:matrix/src/core/logging_service.dart';
import 'package:matrix/src/rust/api/platform.dart' as platform;
import 'package:matrix/src/rust/api/tracing.dart' as tracing;
import 'package:matrix/src/rust/matrix/authentication.dart' as auth;
import 'package:matrix/src/rust/matrix/client.dart' as client;
import 'package:path/path.dart' as path;
import 'package:result_dart/result_dart.dart';
import 'package:sqflite/sqflite.dart';

class InitializationService {
  static final InitializationService _instance =
      InitializationService._internal();
  factory InitializationService() => _instance;
  InitializationService._internal();

  Future<Result<bool>> initialize() async {
    // Initialize Rust logging
    await LoggingService.initializeLogging();
    final String databasesPath = await getDatabasesPath();
    final homeserverUrl = AppConfig.homeserverUrl;
    final String databasePathAsPerHomeserver =
        '$databasesPath${path.separator}${homeserverUrl.path}';
    LoggingService.info(
      'InitializationService',
      'Initializing Matrix app with homeserver: $homeserverUrl and database path: $databasePathAsPerHomeserver',
    );

    try {
      await platform.initPlatform(
        config: platform.TracingConfiguration(
          logLevel: tracing.LogLevel.trace,
          traceLogPacks: platform.TraceLogPacks.values,
          extraTargets: [],
          writeToStdoutOrSystem: true,
          writeToFiles: platform.TracingFileConfiguration(
            path: '$databasePathAsPerHomeserver${path.separator}logs',
            filePrefix: 'matrix',
            fileSuffix: '.log',
          ),
        ),
        useLightweightTokioRuntime: false,
      );
    } catch (e) {
      LoggingService.error('InitializationService', e.toString());
      return Failure(Exception(e.toString()));
    }

    final config = client.ClientConfig(
      sessionPath: databasePathAsPerHomeserver,
      homeserverUrl: homeserverUrl.toString(),
    );

    try {
      final result = await client.configureClient(config: config);
      if (result) {
        return Success(true);
      }
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
    return Failure(Exception('Unknown error'));
  }

  Future<Result<bool>> isUserLoggedIn() async {
    try {
      final result = await auth.isClientAuthenticated();
      return Success(result);
    } catch (e) {
      return Failure(Exception(e.toString()));
    }
  }
}
