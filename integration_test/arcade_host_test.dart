// Run the actual Flutter guest host on a native device with exact signed
// packages and an isolated mock transport. The coordinated live-server test
// remains in integration/experiences_test.dart.
import 'package:integration_test/integration_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bonfire/features/authentication/repositories/session_credential_vault.dart';

import '../test/features/experiences/arcade_lifecycle_test.dart' as lifecycle;
import '../test/features/experiences/canvas_test.dart' as canvas;
import '../test/features/experiences/package_test.dart' as packages;
import '../test/features/experiences/turns_test.dart' as turns;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  lifecycle.main();
  canvas.main();
  packages.main();
  turns.main();
  testWidgets(
    'macOS native credentials still round-trip without sharing a Keychain group',
    (tester) async {
      final vault = PlatformSessionCredentialVault();
      final reference =
          'arcade-validation-${DateTime.now().microsecondsSinceEpoch}';
      var written = false;
      try {
        await vault.write(reference, 'curated-validation-only');
        written = true;
        expect(await vault.read(reference), 'curated-validation-only');
      } finally {
        if (written) await vault.delete(reference);
      }
      expect(await vault.read(reference), isNull);
    },
    skip: kIsWeb || defaultTargetPlatform != TargetPlatform.macOS,
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
