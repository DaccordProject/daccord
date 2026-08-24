import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shortcut guide does not promise unimplemented edit keys', () {
    final guide = File(
      'docs/troubleshooting/keyboard-shortcuts.md',
    ).readAsStringSync();

    expect(guide, isNot(contains('| Up Arrow |')));
    expect(guide, isNot(contains('| Escape |')));
    expect(guide, contains('visible **Cancel** button'));
    expect(guide, contains('context menu and choose **Edit**'));
  });
}
