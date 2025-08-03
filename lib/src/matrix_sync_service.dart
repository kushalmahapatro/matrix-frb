import 'package:matrix/src/rust/api/matrix_client.dart';

class MatrixSyncService {
  static final MatrixSyncService _instance = MatrixSyncService._internal();

  factory MatrixSyncService() => _instance;

  MatrixSyncService._internal();

  late Stream<SyncEvent> _syncStream;

  Stream<SyncEvent> get syncStream => _syncStream;

  Future<void> performInitialSync() async {
    _syncStream = initSyncStream();
    await performInitialSyncWithPolling(startPolling: true);
  }
}
