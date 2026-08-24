import 'package:bonfire/shared/utils/external_url.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _theme = BonfireThemeExtension(
  foreground: Colors.white,
  background: Color(0xFF1e1f22),
  dirtyWhite: Color(0xFFdcddde),
  gray: Color(0xFF949ba4),
  darkGray: Color(0xFF4e5058),
  primary: Color(0xFF5865f2),
  red: Color(0xFFed4245),
  green: Color(0xFF23a55a),
  yellow: Color(0xFFf0b232),
);

Widget _host({
  required String url,
  required ExternalUrlLauncher launcher,
  required ValueNotifier<ExternalUrlOpenResult?> result,
}) {
  return MaterialApp(
    theme: ThemeData(extensions: [_theme]),
    home: Builder(
      builder: (context) => Scaffold(
        body: ElevatedButton(
          onPressed: () async {
            result.value = await openExternalUrl(
              context,
              url,
              launcher: launcher,
            );
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
}

void main() {
  group('tryParseExternalWebUrl', () {
    test('accepts absolute HTTP and HTTPS URLs', () {
      expect(
        tryParseExternalWebUrl('https://docs.example.com/path')?.host,
        'docs.example.com',
      );
      expect(
        tryParseExternalWebUrl('http://localhost:8080/help')?.host,
        'localhost',
      );
    });

    test('rejects state-changing, local, custom, and relative schemes', () {
      for (final url in [
        'daccord://connect?server=evil.example',
        'intent://scan/#Intent;scheme=zxing;end',
        'file:///etc/passwd',
        'javascript:alert(1)',
        'custom-app://run',
        '//example.com/no-scheme',
        '/relative/path',
      ]) {
        expect(tryParseExternalWebUrl(url), isNull, reason: url);
      }
    });
  });

  testWidgets('blocked schemes never reach the platform launcher', (
    tester,
  ) async {
    final launched = <Uri>[];
    final result = ValueNotifier<ExternalUrlOpenResult?>(null);
    await tester.pumpWidget(
      _host(
        url: 'daccord://connect?server=evil.example',
        launcher: (uri) async {
          launched.add(uri);
          return true;
        },
        result: result,
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(launched, isEmpty);
    expect(result.value, ExternalUrlOpenResult.blocked);
    expect(
      find.text('Only valid HTTP and HTTPS links can be opened.'),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
    'shows the destination host and launches only after confirmation',
    (tester) async {
      final launched = <Uri>[];
      final result = ValueNotifier<ExternalUrlOpenResult?>(null);
      await tester.pumpWidget(
        _host(
          url: 'https://downloads.example.com/releases/latest?from=message',
          launcher: (uri) async {
            launched.add(uri);
            return true;
          },
          result: result,
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Open external link?'), findsOneWidget);
      expect(
        find.textContaining('Destination: downloads.example.com'),
        findsOneWidget,
      );
      expect(launched, isEmpty);

      await tester.tap(find.text('Open link'));
      await tester.pumpAndSettle();

      expect(launched, [
        Uri.parse('https://downloads.example.com/releases/latest?from=message'),
      ]);
      expect(result.value, ExternalUrlOpenResult.opened);
    },
  );
}
