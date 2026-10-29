import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shortcut guide documents the edit keys the editor implements', () {
    final guide = File(
      'docs/troubleshooting/keyboard-shortcuts.md',
    ).readAsStringSync();
    final row = File(
      'lib/features/messaging/views/message_pane/message_row.dart',
    ).readAsStringSync();

    // Escape cancels and ↑ edits: documented, and backed by the editor's
    // key handler and the composer's edit-last-message hook.
    expect(guide, contains('| Escape | Cancel the edit |'));
    expect(guide, contains('| ↑ (empty composer) |'));
    expect(row, contains('LogicalKeyboardKey.escape'));
    expect(row, contains('editRequest'));
    expect(guide, contains('visible **Cancel** button'));
    expect(guide, contains('choose **Edit**'));
  });
}
