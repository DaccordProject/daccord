import 'package:bonfire/features/events/controllers/connection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConnectionStatusReachability.isReachable', () {
    test('disconnected is reachable (initial state before any attempt)', () {
      expect(ConnectionStatus.disconnected.isReachable, isTrue);
    });

    test('connecting is reachable', () {
      expect(ConnectionStatus.connecting.isReachable, isTrue);
    });

    test('connected is reachable', () {
      expect(ConnectionStatus.connected.isReachable, isTrue);
    });

    test('ready is reachable', () {
      expect(ConnectionStatus.ready.isReachable, isTrue);
    });

    test('reconnecting is not reachable', () {
      expect(ConnectionStatus.reconnecting.isReachable, isFalse);
    });
  });

  group('ConnectionStatusReachability.isUnreachable', () {
    test('reconnecting is unreachable', () {
      expect(ConnectionStatus.reconnecting.isUnreachable, isTrue);
    });

    test('disconnected is not unreachable (avoids false positive on cold start)',
        () {
      expect(ConnectionStatus.disconnected.isUnreachable, isFalse);
    });

    test('connecting is not unreachable', () {
      expect(ConnectionStatus.connecting.isUnreachable, isFalse);
    });

    test('connected is not unreachable', () {
      expect(ConnectionStatus.connected.isUnreachable, isFalse);
    });

    test('ready is not unreachable', () {
      expect(ConnectionStatus.ready.isUnreachable, isFalse);
    });

    test('isUnreachable is the exact inverse of isReachable for every status',
        () {
      for (final status in ConnectionStatus.values) {
        expect(
          status.isUnreachable,
          equals(!status.isReachable),
          reason: 'status=$status',
        );
      }
    });
  });
}
