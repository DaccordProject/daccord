/// The cheapest possible check that the UI end-to-end pipeline works: a real
/// device, a real widget tree, a real frame. If this fails, nothing else in
/// `integration_test/` will run either — fix the toolchain before reading the
/// other suites' failures.
///
/// See `integration_test/README.md`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders a frame on a real device', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('daccord e2e'))),
    );
    await tester.pumpAndSettle();

    expect(find.text('daccord e2e'), findsOneWidget);
  });
}
