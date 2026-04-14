import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/src/core/calls/incoming_call_present_dedupe.dart';

void main() {
  group('IncomingCallPresentDedupe', () {
    test('allows first present for an event id', () {
      final d = IncomingCallPresentDedupe();
      final t = DateTime.utc(2026, 4, 4, 12);
      expect(d.shouldPresentNow(r'$abc:server', t), isTrue);
    });

    test('blocks duplicate within TTL', () {
      final d = IncomingCallPresentDedupe();
      final t = DateTime.utc(2026, 4, 4, 12);
      expect(d.shouldPresentNow(r'$same:server', t), isTrue);
      expect(
        d.shouldPresentNow(r'$same:server', t.add(const Duration(seconds: 1))),
        isFalse,
      );
    });

    test('allows again after TTL', () {
      final d = IncomingCallPresentDedupe(ttl: const Duration(seconds: 10));
      final t = DateTime.utc(2026, 4, 4, 12);
      expect(d.shouldPresentNow(r'$x:server', t), isTrue);
      expect(
        d.shouldPresentNow(
          r'$x:server',
          t.add(const Duration(seconds: 11)),
        ),
        isTrue,
      );
    });

    test('empty event id is never deduped', () {
      final d = IncomingCallPresentDedupe();
      final t = DateTime.utc(2026, 4, 4, 12);
      expect(d.shouldPresentNow('', t), isTrue);
      expect(d.shouldPresentNow('   ', t), isTrue);
    });

    test('trims event id for dedupe key', () {
      final d = IncomingCallPresentDedupe();
      final t = DateTime.utc(2026, 4, 4, 12);
      const canonical = r'$trimmed:room';
      expect(d.shouldPresentNow('  $canonical  ', t), isTrue);
      expect(
        d.shouldPresentNow(canonical, t.add(const Duration(seconds: 1))),
        isFalse,
      );
    });
  });
}
