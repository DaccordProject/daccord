import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recovery docs only describe available controls', () {
    final troubleshooting = File(
      'docs/troubleshooting/common-issues.md',
    ).readAsStringSync();
    final profiles = File('docs/customization/profiles.md').readAsStringSync();

    expect(troubleshooting, isNot(contains('select **Reconnect**')));
    expect(troubleshooting, isNot(contains('`--profile')));
    expect(profiles, isNot(contains('`--profile')));
    expect(troubleshooting, contains('close and reopen daccord'));
    expect(profiles, contains('only through this in-app screen'));
  });
}
