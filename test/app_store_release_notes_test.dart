import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporary;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('daccord-release-notes-');
    Directory('${temporary.path}/dist').createSync();
    File(
      'dist/app-store-release-notes.sh',
    ).copySync('${temporary.path}/dist/app-store-release-notes.sh');
    File(
      '${temporary.path}/pubspec.yaml',
    ).writeAsStringSync('name: release_notes_test\nversion: 1.2.3+4\n');
  });

  tearDown(() => temporary.deleteSync(recursive: true));

  Future<ProcessResult> runScript(String override, {String tag = 'v1.2.3'}) {
    File(
      '${temporary.path}/dist/release-notes.txt',
    ).writeAsStringSync(override);
    return Process.run(
      'bash',
      ['dist/app-store-release-notes.sh'],
      workingDirectory: temporary.path,
      environment: {
        ...Platform.environment,
        'GITHUB_REF_TYPE': 'tag',
        'GITHUB_REF_NAME': tag,
      },
    );
  }

  test(
    'accepts handwritten notes only for the current version and tag',
    () async {
      final result = await runScript(
        '# Release version: 1.2.3\n• Current release copy.\n',
      );

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, contains('Using hand-written notes'));
      expect(
        File(
          '${temporary.path}/fastlane/metadata/ios/en-US/release_notes.txt',
        ).readAsStringSync(),
        '• Current release copy.\n',
      );
    },
  );

  test('rejects an override for an old app version', () async {
    final result = await runScript('# Release version: 1.2.2\n• Stale copy.\n');

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('pubspec.yaml is 1.2.3'));
  });

  test('rejects an override that does not match the release tag', () async {
    final result = await runScript(
      '# Release version: 1.2.3\n• Wrong tag copy.\n',
      tag: 'v1.2.4',
    );

    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('release tag is v1.2.4'));
  });

  test(
    'rejects handwritten notes without an explicit version marker',
    () async {
      final result = await runScript('• Unversioned copy.\n');

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains("no '# Release version: x.y.z' marker"));
    },
  );
}
