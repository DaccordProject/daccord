import 'package:bonfire/features/user/views/accord_account_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractTotpSecret', () {
    test('returns null for null input', () {
      expect(extractTotpSecret(null), isNull);
    });

    test('extracts secret from a standard otpauth URI', () {
      const uri =
          'otpauth://totp/user%40example.com?secret=JBSWY3DPEHPK3PXP&issuer=ExampleServer';
      expect(extractTotpSecret(uri), 'JBSWY3DPEHPK3PXP');
    });

    test('extracts secret when it is not the first query param', () {
      const uri =
          'otpauth://totp/label?issuer=Foo&secret=BASE32ABC&digits=6';
      expect(extractTotpSecret(uri), 'BASE32ABC');
    });

    test('is case-insensitive for the secret key', () {
      const uri = 'otpauth://totp/label?Secret=MIXEDCASE123';
      expect(extractTotpSecret(uri), 'MIXEDCASE123');
    });

    test('returns the input unchanged when there is no secret param', () {
      const plain = 'JBSWY3DPEHPK3PXP';
      expect(extractTotpSecret(plain), plain);
    });

    test('returns the input unchanged for a plain secret (no otpauth scheme)', () {
      const plain = 'ABC123DEF456';
      expect(extractTotpSecret(plain), plain);
    });
  });
}
