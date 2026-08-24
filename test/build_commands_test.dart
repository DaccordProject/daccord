import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('documented and scripted Android builds select the required flavor', () {
    final script = File('scripts/build.sh').readAsStringSync();
    final readme = File('README.md').readAsStringSync();
    final scriptReadme = File('scripts/README.md').readAsStringSync();

    expect(script, contains(r'$FLUTTER build apk --flavor github'));
    expect(script, contains(r'$FLUTTER build appbundle --flavor play'));
    expect(readme, contains('flutter run --flavor github'));
    expect(readme, contains('flutter build apk     --flavor github'));
    expect(readme, contains('flutter build appbundle --flavor play'));
    expect(scriptReadme, contains('scripts/start.sh --flavor github'));
  });

  test('Web artifacts are labeled JavaScript and built without --wasm', () {
    const buildSurface = [
      'CLAUDE.md',
      'README.md',
      'scripts/README.md',
      'scripts/build.sh',
      '.github/workflows/ci.yml',
      '.github/workflows/release.yml',
      'docs/getting-started/installation.md',
    ];
    const commandFiles = [
      'CLAUDE.md',
      'README.md',
      'scripts/build.sh',
      '.github/workflows/ci.yml',
      '.github/workflows/release.yml',
    ];

    for (final path in buildSurface) {
      final contents = File(path).readAsStringSync();
      expect(contents, contains('Web (JavaScript)'), reason: path);
      expect(
        contents.toLowerCase(),
        isNot(contains('wasm')),
        reason: '$path must not label the JavaScript artifact as WASM',
      );
    }

    for (final path in commandFiles) {
      final commands = File(
        path,
      ).readAsLinesSync().where((line) => line.contains('build web'));
      expect(commands, isNotEmpty, reason: path);
      for (final command in commands) {
        expect(
          command,
          isNot(contains('--wasm')),
          reason: '$path labels this artifact as JavaScript',
        );
      }
    }
  });

  test('CI and local docs use the generated-code cleanliness check', () {
    final ci = File('.github/workflows/ci.yml').readAsStringSync();
    final script = File('scripts/codegen.sh').readAsStringSync();
    final readme = File('README.md').readAsStringSync();

    expect(ci, contains('run: scripts/codegen.sh --check'));
    expect(script, contains("git diff --name-only HEAD -- '*.g.dart'"));
    expect(
      script,
      contains("git ls-files --others --exclude-standard -- '*.g.dart'"),
    );
    expect(readme, contains('scripts/codegen.sh --check'));
  });
}
