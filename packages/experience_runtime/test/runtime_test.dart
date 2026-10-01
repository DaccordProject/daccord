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
  test(
    'i32 decoding and overflow agree across native and JavaScript hosts',
    () {
      for (final values in [
        (2147483647, 2147483647, 1),
        (-2147483648, -1, -2147483648),
        (65537, 65537, 131073),
      ]) {
        // read_state returns a wrapped i32; multiplication then wraps exactly,
        // including products too large for a JavaScript Number to represent.
        var result = 0;
        final module = ExperienceModule.decode(
          testModule(
            render: [
              0x41,
              ...sint(values.$1),
              0x41,
              ...sint(values.$2),
              0x6c,
              0x1a,
            ],
            input: [0x41, 0, 0x41, 0, 0x41, 0, 0x10, 2],
          ),
        );
        module.invoke(
          'render',
          [],
          readState: (k, i) => 0,
          grantValid: () => true,
        );
        // A second module makes the wrapped product observable via draw.value.
        final observable = ExperienceModule.decode(
          testModule(
            render: [
              for (var n = 0; n < 6; n++) ...[0x41, 0],
              0x41,
              ...sint(values.$1),
              0x41,
              ...sint(values.$2),
              0x6c,
              0x10,
              1,
            ],
          ),
        );
        if (values.$3.abs() > 65535) {
          expect(
            () => observable.invoke(
              'render',
              [],
              readState: (k, i) => 0,
              grantValid: () => true,
            ),
            throwsStateError,
          );
        } else {
          result = observable
              .invoke(
                'render',
                [],
                readState: (k, i) => 0,
                grantValid: () => true,
              )
              .drawings
              .single
              .values
              .last;
          expect(result, values.$3);
        }
      }
    },
  );
  test(
    'exponential acyclic calls and excessive call depth exhaust host limits',
    () {
      final helpers = <List<int>>[[]];
      for (var i = 1; i < 20; i++) {
        helpers.add([0x10, ...uint(i + 2), 0x10, ...uint(i + 2)]);
      }
      final fuel = ExperienceModule.decode(
        testModule(helpers: helpers, render: [0x10, ...uint(22)]),
      );
      expect(
        () => fuel.invoke(
          'render',
          [],
          readState: (k, i) => 0,
          grantValid: () => true,
        ),
        throwsStateError,
      );
      final chain = <List<int>>[[]];
      for (var i = 1; i < 34; i++) {
        chain.add([0x10, ...uint(i + 2)]);
      }
      final depth = ExperienceModule.decode(
        testModule(helpers: chain, render: [0x10, ...uint(36)]),
      );
      expect(
        () => depth.invoke(
          'render',
          [],
          readState: (k, i) => 0,
          grantValid: () => true,
        ),
        throwsStateError,
      );
    },
  );
}
