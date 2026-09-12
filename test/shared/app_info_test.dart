import 'package:bonfire/shared/app_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('public website URLs', () {
    test('privacy and help links are absolute HTTPS URLs on the website', () {
      for (final url in [kDaccordHelpUrl, kDaccordPrivacyPolicyUrl]) {
        final uri = Uri.parse(url);
        expect(uri.scheme, 'https', reason: url);
        expect(uri.host, Uri.parse(kDaccordWebsiteUrl).host, reason: url);
      }
    });
  });
}
