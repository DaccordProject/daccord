/// Unit coverage for the pure decisions in
/// `multi_instance/support/app_instance.dart` — fast and hermetic, unlike the
/// suite itself which needs a display, a built release bundle, and a server.
import 'package:flutter_test/flutter_test.dart';

import '../../multi_instance/support/app_instance.dart';

void main() {
  group('chooseBundle', () {
    test('prefers release when both exist', () {
      expect(
        chooseBundle(releaseExists: true, debugExists: true),
        BundleChoice.release,
      );
    });

    test('release only', () {
      expect(
        chooseBundle(releaseExists: true, debugExists: false),
        BundleChoice.release,
      );
    });

    test(
      'never falls back to debug — a debug bundle launched directly never '
      'runs main(), so it is reported distinctly rather than picked',
      () {
        expect(
          chooseBundle(releaseExists: false, debugExists: true),
          BundleChoice.debugOnly,
        );
      },
    );

    test('neither exists', () {
      expect(
        chooseBundle(releaseExists: false, debugExists: false),
        BundleChoice.none,
      );
    });
  });
}
