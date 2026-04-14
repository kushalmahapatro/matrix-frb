import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Tracks device connectivity so UI can stay usable offline and gate network-only actions.
class NetworkAvailability extends ChangeNotifier {
  NetworkAvailability() {
    _subscription = Connectivity().onConnectivityChanged.listen(_apply);
    unawaited(_bootstrap());
  }

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  bool _online = true;

  /// Best-effort: any non-[ConnectivityResult.none] interface counts as online.
  bool get isOnline => _online;

  Future<void> _bootstrap() async {
    try {
      final r = await _connectivity.checkConnectivity();
      _apply(r);
    } catch (_) {
      _online = true;
      notifyListeners();
    }
  }

  void _apply(List<ConnectivityResult> results) {
    final hasPath =
        results.any((c) => c != ConnectivityResult.none);
    if (hasPath == _online) return;
    _online = hasPath;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
