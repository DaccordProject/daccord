import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the resolved dependency lock does not restore removed networking', () {
    final lock = File('pubspec.lock');
    expect(lock.existsSync(), isTrue);
    // CLAUDE.md: firebridge is gone and must not come back through a
    // transitive dependency or a reverted pubspec edit.
    expect(lock.readAsStringSync().toLowerCase(), isNot(contains('firebridge')));
  });

  test('stale macOS swiftpm locks are not tracked', () {
    for (final path in [
      'macos/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved',
      'macos/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved',
    ]) {
      expect(
        File(path).existsSync(),
        isFalse,
        reason: '$path is stale because macOS uses only a local Swift package',
      );
    }
  });
}
