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

    test('uses last @ so a qualified spaceId is preserved', () {
      // A space ID that is already qualified (e.g. from another federated hop)
      // still splits correctly: everything before the final @ is the space id.
      final addr = parseFederatedAddress('42@olddomain.example@newdomain.example');
      expect(addr?.spaceId, '42@olddomain.example');
      expect(addr?.domain, 'newdomain.example');
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

    test('preserves qualified spaceId in federate deep link', () {
      final parsed = ServerUri.parseDeepLink(
          'daccord://federate/42@olddomain.example@newdomain.example');
      expect(parsed?.route, 'federate');
      expect(parsed?.spaceId, '42@olddomain.example');
      expect(parsed?.domain, 'newdomain.example');
    });
  });
}
