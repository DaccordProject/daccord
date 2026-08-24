import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runtime app assets do not load remote fonts', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final webShell = File('web/index.html').readAsStringSync();
    final appSources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');

    expect(pubspec, isNot(contains('google_fonts:')));
    expect(webShell, isNot(contains('fonts.googleapis.com')));
    expect(appSources, isNot(contains('package:google_fonts/')));
  });

  test('public claims link to the network disclosure', () {
    final readme = File('README.md').readAsStringSync();
    final troubleshooting = File(
      'docs/troubleshooting/common-issues.md',
    ).readAsStringSync();
    final disclosure = File('docs/privacy-network.md').readAsStringSync();

    expect(readme, contains('docs/privacy-network.md'));
    expect(troubleshooting, contains('../privacy-network.md'));
    for (final destination in [
      'master.daccord.gg',
      'api.github.com',
      'LiveKit',
      'CDN',
      'External media',
    ]) {
      expect(disclosure, contains(destination));
    }
  });
}
