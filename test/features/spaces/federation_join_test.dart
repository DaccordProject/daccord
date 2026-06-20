import 'package:bonfire/features/spaces/controllers/federation_join.dart';
import 'package:bonfire/features/server/utils/server_uri.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseFederatedAddress', () {
    test('splits spaceId@domain', () {
      final addr = parseFederatedAddress('42@b.example');
      expect(addr?.spaceId, '42');
      expect(addr?.domain, 'b.example');
    });

    test('trims whitespace', () {
      final addr = parseFederatedAddress('  42@b.example  ');
      expect(addr?.spaceId, '42');
      expect(addr?.domain, 'b.example');
    });

    test('rejects input without a domain', () {
      expect(parseFederatedAddress('42'), isNull);
      expect(parseFederatedAddress('42@'), isNull);
      expect(parseFederatedAddress('@b.example'), isNull);
    });
  });

  group('federate deep link', () {
    test('parses daccord://federate/<spaceId>@<domain>', () {
      final parsed = ServerUri.parseDeepLink('daccord://federate/42@b.example');
      expect(parsed?.route, 'federate');
      expect(parsed?.spaceId, '42');
      expect(parsed?.domain, 'b.example');
    });

    test('rejects a federate link without a domain', () {
      expect(ServerUri.parseDeepLink('daccord://federate/42'), isNull);
    });
  });
}
