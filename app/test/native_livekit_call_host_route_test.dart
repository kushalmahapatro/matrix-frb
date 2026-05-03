import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/src/core/calls/native_livekit_call_host.dart';

void main() {
  final host = NativeLiveKitCallHost.instance;

  setUp(() {
    host.debugResetForTest();
  });

  tearDown(() {
    host.debugResetForTest();
  });

  group('NativeLiveKitCallHost call route tracking', () {
    test('markCallScreenRouteOpening/Closed mirrors push and pop', () {
      expect(host.callScreenRouteOnStack, isFalse);
      host.markCallScreenRouteOpening();
      expect(host.callScreenRouteOnStack, isTrue);
      host.markCallScreenRouteClosed();
      expect(host.callScreenRouteOnStack, isFalse);
    });

    test('routeVisible can be false while call route is still on stack', () {
      host.markRouteVisible(false);
      host.markCallScreenRouteOpening();
      expect(host.routeVisible, isFalse);
      expect(host.callScreenRouteOnStack, isTrue);
    });

    test('debugResetForTest clears flags', () {
      host.markRouteVisible(true);
      host.markCallScreenRouteOpening();
      host.debugResetForTest();
      expect(host.routeVisible, isFalse);
      expect(host.callScreenRouteOnStack, isFalse);
    });
  });
}
