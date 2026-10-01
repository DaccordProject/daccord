import 'dart:typed_data';

/// The v1 profile intentionally has no linear memory, tables, branches, loops,
/// globals, indirect calls or WASI. Modules using other Wasm features fail closed.
class ExperienceModule {
  static const maxBytes = 65536;
  static const instructionBudget = 10000;
  final List<_Type> _types;
  final List<int> _functions;
  final List<_Body> _bodies;
  final Map<String, int> _exports;

  ExperienceModule._(this._types, this._functions, this._bodies, this._exports);

  factory ExperienceModule.decode(Uint8List bytes) {
    if (bytes.length > maxBytes)
      throw const FormatException('Module too large');
    final r = _Reader(bytes);
    if (r.take(8).join(',') != '0,97,115,109,1,0,0,0') {
      throw const FormatException('Expected WebAssembly core v1');
    }
    final types = <_Type>[];
    final functions = <int>[];
    final bodies = <_Body>[];
    final exports = <String, int>{};
    var lastSection = 0;
    while (!r.done) {
      final id = r.byte();
      final section = _Reader(Uint8List.fromList(r.take(r.uint())));
      if (id <= lastSection || ![1, 2, 3, 7, 10].contains(id)) {
        throw const FormatException('Unsupported or duplicate Wasm section');
      }
      lastSection = id;
      final count = section.uint();
      if (count > 256) throw const FormatException('Section limit exceeded');
      switch (id) {
        case 1:
          for (var i = 0; i < count; i++) {
            if (section.byte() != 0x60)
              throw const FormatException('Function type required');
            final params = section.uint();
            if (params > 8) throw const FormatException('Too many arguments');
            for (var p = 0; p < params; p++) {
              if (section.byte() != 0x7f)
                throw const FormatException('Only i32 supported');
            }
            final results = section.uint();
            if (results > 1 || (results == 1 && section.byte() != 0x7f)) {
              throw const FormatException('Only one i32 result supported');
            }
            types.add(_Type(params, results));
          }
        case 2:
          if (count != 3)
            throw const FormatException(
              'Expected three versioned host imports',
            );
          const names = ['read_state', 'draw', 'action'];
          const signatures = [(2, 1), (7, 0), (3, 0)];
          for (var i = 0; i < count; i++) {
            if (section.name() != 'daccord_v1' ||
                section.name() != names[i] ||
                section.byte() != 0) {
              throw const FormatException('Denied host import');
            }
            final index = section.uint();
            if (index >= types.length ||
                (types[index].params, types[index].results) != signatures[i]) {
              throw const FormatException('Invalid host signature');
            }
            functions.add(index);
          }
        case 3:
          for (var i = 0; i < count; i++) {
            final index = section.uint();
            if (index >= types.length)
              throw const FormatException('Unknown function type');
            functions.add(index);
          }
        case 7:
          if (count != 2)
            throw const FormatException('Expected render and input exports');
          for (var i = 0; i < count; i++) {
            final name = section.name();
            if (!['render', 'input'].contains(name) ||
                exports.containsKey(name) ||
                section.byte() != 0) {
              throw const FormatException('Invalid export');
            }
            final index = section.uint();
            if (index < 3 || index >= functions.length)
              throw const FormatException('Invalid export index');
            final type = types[functions[index]];
            if (type.results != 0 ||
                type.params != (name == 'render' ? 0 : 3)) {
              throw const FormatException('Invalid export signature');
            }
            exports[name] = index;
          }
        case 10:
          for (var i = 0; i < count; i++) {
            final body = _Reader(
              Uint8List.fromList(section.take(section.uint())),
            );
            if (body.uint() != 0)
              throw const FormatException('Local allocation is not supported');
            final instructions = <_Instruction>[];
            while (!body.done) {
              final op = body.byte();
              if (op == 0x0b) {
                if (!body.done)
                  throw const FormatException('Trailing function bytes');
                break;
              }
              if (![0x41, 0x20, 0x10, 0x1a, 0x6a, 0x6b, 0x6c].contains(op)) {
                throw const FormatException(
                  'Instruction outside bounded v1 profile',
                );
              }
              instructions.add(
                _Instruction(
                  op,
                  op == 0x41
                      ? body.sint()
                      : ([0x20, 0x10].contains(op) ? body.uint() : 0),
                ),
              );
              if (instructions.length > 4096)
                throw const FormatException('Too many instructions');
              if (body.done)
                throw const FormatException('Missing function end');
            }
            bodies.add(_Body(instructions));
          }
      }
      if (!section.done) throw const FormatException('Trailing section bytes');
    }
    if (lastSection != 10 ||
        functions.length != bodies.length + 3 ||
        exports.length != 2) {
      throw const FormatException('Incomplete module');
    }
    // Only calls to earlier functions are admitted. This proves the call graph
    // is acyclic before any guest instruction or host callback executes.
    for (var i = 0; i < bodies.length; i++) {
      final own = i + 3;
      final type = types[functions[own]];
      var stack = 0;
      for (final instruction in bodies[i].instructions) {
        switch (instruction.op) {
          case 0x41:
            stack++;
          case 0x20:
            if (instruction.value >= type.params)
              throw const FormatException('Invalid local index');
            stack++;
          case 0x10:
            if (instruction.value >= own)
              throw const FormatException('Recursive or forward call denied');
            final called = types[functions[instruction.value]];
            if (stack < called.params)
              throw const FormatException('Stack underflow');
            stack += called.results - called.params;
          case 0x1a:
            if (stack < 1) throw const FormatException('Stack underflow');
            stack--;
          default:
            if (stack < 2) throw const FormatException('Stack underflow');
            stack--;
        }
        if (stack > 128) throw const FormatException('Stack limit exceeded');
      }
      if (stack != type.results)
        throw const FormatException('Invalid result stack');
    }
    return ExperienceModule._(types, functions, bodies, exports);
  }

  /// Hosts supply scoped state, never tokens or arbitrary network callbacks.
  /// A grant is checked before execution and every host call. Frames/actions
  /// are returned atomically; nothing is committed after a failed invocation.
  ExperienceOutput invoke(
    String export,
    List<int> args, {
    required int Function(int key, int index) readState,
    required bool Function() grantValid,
  }) {
    final index = _exports[export];
    if (index == null || args.length != _types[_functions[index]].params) {
      throw ArgumentError('Invalid invocation');
    }
    final drawings = <ExperienceDrawing>[];
    final actions = <ExperienceAction>[];
    var fuel = instructionBudget;
    var reads = 0;
    void check() {
      if (!grantValid()) throw StateError('Experience grant revoked');
      if (--fuel < 0)
        throw StateError('Experience instruction budget exceeded');
    }

    int? call(int function, List<int> parameters, int depth) {
      check();
      if (depth > 32) throw StateError('Experience call depth exceeded');
      if (function < 3) {
        switch (function) {
          case 0:
            if (++reads > 256 || parameters.any((v) => v < 0 || v > 1024))
              throw StateError('State read limit exceeded');
            return _i32(readState(parameters[0], parameters[1]));
          case 1:
            if (export != 'render' ||
                drawings.length >= 128 ||
                parameters[0] < 0 ||
                parameters[0] > 2 ||
                parameters.skip(1).take(5).any((v) => v < 0 || v > 1024) ||
                parameters[6].abs() > 65535) {
              throw StateError('Invalid drawing command');
            }
            drawings.add(ExperienceDrawing(List.unmodifiable(parameters)));
          case 2:
            if (export != 'input' ||
                actions.isNotEmpty ||
                parameters.any((v) => v < 0 || v > 1024))
              throw StateError('Invalid action');
            actions.add(
              ExperienceAction(parameters[0], parameters[1], parameters[2]),
            );
        }
        return null;
      }
      final stack = <int>[];
      for (final instruction in _bodies[function - 3].instructions) {
        check();
        switch (instruction.op) {
          case 0x41:
            stack.add(instruction.value);
          case 0x20:
            stack.add(parameters[instruction.value]);
          case 0x10:
            final count = _types[_functions[instruction.value]].params;
            final start = stack.length - count;
            final values = stack.sublist(start);
            stack.removeRange(start, stack.length);
            final result = call(instruction.value, values, depth + 1);
            if (result != null) stack.add(result);
          case 0x1a:
            stack.removeLast();
          default:
            final b = stack.removeLast();
            final a = stack.removeLast();
            stack.add(
              _i32(switch (instruction.op) {
                0x6a => a + b,
                0x6b => a - b,
                _ => a * b,
              }),
            );
        }
      }
      return stack.isEmpty ? null : stack.single;
    }

    call(index, args.map(_i32).toList(), 0);
    check();
    return ExperienceOutput(
      List.unmodifiable(drawings),
      List.unmodifiable(actions),
    );
  }
}

int _i32(int value) => value.toSigned(32);

class ExperienceOutput {
  final List<ExperienceDrawing> drawings;
  final List<ExperienceAction> actions;
  const ExperienceOutput(this.drawings, this.actions);
}

/// kind, semantic id, x, y, width, height, value; logical canvas is 1024².
class ExperienceDrawing {
  final List<int> values;
  const ExperienceDrawing(this.values);
}

class ExperienceAction {
  final int kind;
  final int a;
  final int b;
  const ExperienceAction(this.kind, this.a, this.b);
}

class _Type {
  final int params;
  final int results;
  const _Type(this.params, this.results);
}

class _Body {
  final List<_Instruction> instructions;
  const _Body(this.instructions);
}

class _Instruction {
  final int op;
  final int value;
  const _Instruction(this.op, this.value);
}

class _Reader {
  final Uint8List bytes;
  var position = 0;
  _Reader(this.bytes);
  bool get done => position == bytes.length;
  int byte() {
    if (position >= bytes.length)
      throw const FormatException('Truncated module');
    return bytes[position++];
  }

  List<int> take(int length) {
    if (length < 0 || length > bytes.length - position)
      throw const FormatException('Truncated module');
    final value = bytes.sublist(position, position + length);
    position += length;
    return value;
  }

  int uint() => _leb(false);
  int sint() => _leb(true);
  int _leb(bool signed) {
    var value = 0;
    for (var i = 0; i < 5; i++) {
      final b = byte();
      value |= (b & 0x7f) << (7 * i);
      if (b & 0x80 == 0) {
        if (signed && b & 0x40 != 0) value |= -(1 << (7 * (i + 1)));
        if (signed
            ? value < -2147483648 || value > 2147483647
            : value > 4294967295)
          throw const FormatException('Invalid i32 LEB');
        return value;
      }
    }
    throw const FormatException('Invalid LEB');
  }

  String name() {
    final data = take(uint());
    if (data.length > 64 || data.any((b) => b > 127 || b < 32))
      throw const FormatException('Invalid name');
    return String.fromCharCodes(data);
  }
}
