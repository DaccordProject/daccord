import 'package:bonfire/features/updates/models/app_release.dart';
import 'package:bonfire/features/updates/views/release_notes_dialog.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _release = AppRelease(
  version: '1.3.0',
  name: 'v1.3.0',
  notes: '## Fixed\n\n- **drag and drop** attachments\n- forum replies',
  url: 'https://example/releases/v1.3.0',
  publishedAt: '',
);

/// Collects every rendered paragraph so markdown output can be asserted on
/// without depending on how the viewer splits spans.
String _renderedText(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText))
    .map((w) => w.text.toPlainText())
    .join('\n');

Widget _host(AppRelease release, {Size size = const Size(800, 600)}) =>
    MaterialApp(
      theme: buildAppTheme(AppThemePreset.dark),
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showReleaseNotesDialog(context, release),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('renders the notes as markdown under a "What\'s new" title',
      (tester) async {
    await tester.pumpWidget(_host(_release));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text("What's new in v1.3.0"), findsOneWidget);

    final text = _renderedText(tester);
    // Markdown was applied, not dumped verbatim.
    expect(text, contains('Fixed'));
    expect(text, contains('drag and drop'));
    expect(text, contains('forum replies'));
    expect(text, isNot(contains('##')));
    expect(text, isNot(contains('**')));
  });

  testWidgets('"Got it" dismisses the dialog', (tester) async {
    await tester.pumpWidget(_host(_release));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(ReleaseNotesDialog), findsOneWidget);

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.byType(ReleaseNotesDialog), findsNothing);
  });

  testWidgets('tapping the barrier also dismisses it', (tester) async {
    await tester.pumpWidget(_host(_release));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(ReleaseNotesDialog), findsNothing);
  });

  testWidgets('offers a GitHub link only when the release has a URL',
      (tester) async {
    await tester.pumpWidget(_host(_release));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('View on GitHub'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      _host(
        const AppRelease(
          version: '1.3.0',
          name: 'v1.3.0',
          notes: 'notes',
          url: '',
          publishedAt: '',
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('View on GitHub'), findsNothing);
    expect(find.text('Got it'), findsOneWidget);
  });

  testWidgets('a long changelog scrolls instead of overflowing a small window',
      (tester) async {
    final long = List.generate(60, (i) => '- change number $i').join('\n');
    await tester.pumpWidget(
      _host(
        AppRelease(
          version: '1.3.0',
          name: 'v1.3.0',
          notes: long,
          url: '',
          publishedAt: '',
        ),
        size: const Size(360, 640),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(SingleChildScrollView), findsWidgets);
    // Actions stay reachable (the notes scroll, the dialog doesn't overflow).
    expect(find.text('Got it'), findsOneWidget);
  });
}
