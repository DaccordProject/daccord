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
}
