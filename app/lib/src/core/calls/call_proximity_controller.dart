import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:proximity_sensor/proximity_sensor.dart';

/// Enables platform proximity behavior during earpiece voice calls (Android screen-off;
/// iOS sensor stream is registered for system-style behavior where supported).
class CallProximityController {
  StreamSubscription<int>? _sub;
  bool _androidScreenOff = false;

  Future<void> activateEarpieceProximity() async {
    await dispose();
    if (kIsWeb) return;
    if (!Platform.isIOS && !Platform.isAndroid) return;

    if (Platform.isAndroid) {
      try {
        await ProximitySensor.setProximityScreenOff(true);
        _androidScreenOff = true;
      } catch (e) {
        debugPrint('CallProximityController: setProximityScreenOff: $e');
      }
    }

    try {
      _sub = ProximitySensor.events.listen((_) {});
    } catch (e) {
      debugPrint('CallProximityController: events.listen: $e');
    }
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    if (!kIsWeb && Platform.isAndroid && _androidScreenOff) {
      try {
        await ProximitySensor.setProximityScreenOff(false);
      } catch (e) {
        debugPrint('CallProximityController: disable screen off: $e');
      }
      _androidScreenOff = false;
    }
  }
}
