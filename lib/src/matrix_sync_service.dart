import 'package:matrix/src/rust/matrix/sync_service.dart';

class MatrixSyncService {
  static final MatrixSyncService _instance = MatrixSyncService._internal();

  factory MatrixSyncService() => _instance;

  MatrixSyncService._internal();

  Future<void> performInitialSync() async {
    await startSyncService();
  }
}
