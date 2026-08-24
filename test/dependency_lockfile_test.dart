import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tracked dependency locks do not restore removed networking stacks', () {
    final exampleLock = File('packages/markdown_viewer/example/pubspec.lock');
    expect(exampleLock.existsSync(), isTrue);
    final contents = exampleLock.readAsStringSync().toLowerCase();
    expect(contents, isNot(contains('firebridge')));

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
