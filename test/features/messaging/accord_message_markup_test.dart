import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/messaging/views/box/accord_markdown_box.dart';
import 'package:bonfire/features/messaging/views/box/accord_message_markup.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Joins the plain text of every [RichText] paragraph on screen (skipping the
/// chip RichTexts, whose root span is a [WidgetSpan]).
String _paragraphText(WidgetTester tester) {
  final buffer = StringBuffer();
  for (final element in find.byType(RichText).evaluate()) {
    final span = (element.widget as RichText).text;
    if (span is WidgetSpan) continue;
    buffer.write(span.toPlainText());
  }
  return buffer.toString();
}

Widget _host(Widget child) => MaterialApp(
      theme: buildAppTheme(AppThemePreset.dark),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets(
    'renders markdown and a channel chip together; chip is tappable',
    (tester) async {
      String? tapped;
      final markup = buildAccordMarkup(
        AccordMarkupContext(
          channelByName: {
            'general': AccordChannel(id: 'c1', name: 'general', type: 'text'),
          },
          onTapChannel: (id) => tapped = id,
        ),
      );

      await tester.pumpWidget(
        _host(
          AccordMarkdownBox(
            content: 'see **bold** in #general now',
            syntaxExtensions: markup.syntaxes,
            elementBuilders: markup.builders,
          ),
        ),
      );
      await tester.pump();

      // Markdown was applied (asterisks stripped), not shown verbatim.
      final text = _paragraphText(tester);
      expect(text, contains('bold'));
      expect(text, isNot(contains('*')));

      // The channel rendered as a chip pill, and tapping it fires the callback.
      expect(find.text('#general'), findsOneWidget);
      await tester.tap(find.text('#general'));
      await tester.pump();
      expect(tapped, 'c1');
    },
  );

  testWidgets(
    'chips @everyone but leaves email-like @ handles as plain text',
    (tester) async {
      final markup = buildAccordMarkup(const AccordMarkupContext());

      await tester.pumpWidget(
        _host(
          AccordMarkdownBox(
            content: 'mail me at email@host then ping @everyone',
            syntaxExtensions: markup.syntaxes,
            elementBuilders: markup.builders,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('@everyone'), findsOneWidget);
      expect(_paragraphText(tester), contains('email@host'));
    },
  );

  testWidgets('unresolved #channel stays plain text (no chip)', (tester) async {
    final markup = buildAccordMarkup(const AccordMarkupContext());

    await tester.pumpWidget(
      _host(
        AccordMarkdownBox(
          content: 'look at #nowhere please',
          syntaxExtensions: markup.syntaxes,
          elementBuilders: markup.builders,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('#nowhere'), findsNothing);
    expect(_paragraphText(tester), contains('#nowhere'));
  });
}
