/// Run the actual Flutter guest host on a native device with exact signed
/// packages and an isolated mock transport. The coordinated live-server test
/// remains in integration/experiences_test.dart.
import 'package:integration_test/integration_test.dart';

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
}
