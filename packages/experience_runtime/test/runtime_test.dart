@TestOn('vm || browser')
library;

import 'dart:typed_data';
import 'package:experience_runtime/experience_runtime.dart';
import 'package:test/test.dart';
import 'fixtures.dart';

void main() {
  test('chess draws authoritative pieces and submits the selected move', () {
    final module = ExperienceModule.decode(chess());
    final frame = module.invoke(
      'render',
      [],
      readState: (k, i) => i % 13,
      grantValid: () => true,
    );
    expect(frame.drawings, hasLength(64));
    expect(frame.drawings[9].values, [0, 9, 128, 768, 128, 128, 9]);
    final action = module
        .invoke(
          'input',
          [0, 12, 28],
          readState: (k, i) => 0,
          grantValid: () => true,
        )
        .actions
        .single;
    expect([action.kind, action.a, action.b], [0, 12, 28]);
  });
  test('Pong uses the same state and drawing boundary', () {
    final frame = ExperienceModule.decode(
      pong(),
    ).invoke('render', [], readState: (k, i) => i * 10, grantValid: () => true);
    expect(frame.drawings, hasLength(3));
    expect(frame.drawings.last.values, [1, 2, 80, 90, 100, 110, 2]);
  });
  test('infinite loops and recursion are rejected before execution', () {
    for (final bytes in [loop(), recursive()]) {
      expect(() => ExperienceModule.decode(bytes), throwsFormatException);
    }
  });
  test('malformed and oversized modules fail closed', () {
    final bytes = chess();
    for (var length = 0; length < bytes.length; length++) {
      expect(
        () => ExperienceModule.decode(Uint8List.sublistView(bytes, 0, length)),
        throwsFormatException,
      );
    }
    expect(
      () => ExperienceModule.decode(Uint8List(65537)),
      throwsFormatException,
    );
    final denied = Uint8List.fromList(bytes);
    denied[8] = 5; // memory section is always denied, including growth attacks.
    expect(() => ExperienceModule.decode(denied), throwsFormatException);
  });
  test('render cannot submit actions and output is bounded', () {
    for (final bytes in [deniedAction(), outputFlood()]) {
      expect(
        () => ExperienceModule.decode(
          bytes,
        ).invoke('render', [], readState: (k, i) => 0, grantValid: () => true),
        throwsStateError,
      );
    }
  });
  test('revocation during execution discards the entire frame', () {
    var valid = true;
    expect(
      () => ExperienceModule.decode(chess()).invoke(
        'render',
        [],
        readState: (k, i) {
          if (i == 20) valid = false;
          return 0;
        },
        grantValid: () => valid,
      ),
      throwsStateError,
    );
  });
}
