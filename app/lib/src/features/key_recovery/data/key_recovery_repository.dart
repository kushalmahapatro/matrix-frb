import 'package:matrix_sdk/matrix_sdk.dart';

class KeyRecoveryRepository {
  KeyRecoveryRepository(this._client);

  final MatrixClient _client;

  Future<void> refreshState() => _client.refreshRecoveryState();

  Future<String> getState() => _client.getRecoveryState();

  Future<bool> backupExistsOnServer() => _client.backupExistsOnServer();

  Future<String> enableWithPassphrase(String passphrase) =>
      _client.enableRecoveryWithPassphrase(passphrase: passphrase);

  Future<void> recoverWithPassphrase(String passphrase) =>
      _client.recoverWithPassphrase(passphrase: passphrase);
}
