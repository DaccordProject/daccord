import 'package:integration_test/integration_test.dart';
import '../test/features/experiences/pong_live_test.dart' as pong;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  pong.main();
}
