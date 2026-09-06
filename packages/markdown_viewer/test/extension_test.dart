import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_viewer/markdown_viewer.dart';

/// A minimal `#tag` inline syntax, standing in for a consumer's extension.
class ExampleSyntax extends MdInlineSyntax {
  ExampleSyntax() : super(RegExp(r'#[^#]+?(?=\s+|$)'));

  @override
  MdInlineObject? parse(MdInlineParser parser, Match match) {
    final markers = [parser.consume()];
    final content = parser.consumeBy(match[0]!.length - 1);
    final children = content.map((e) => MdText.fromSpan(e)).toList();

    return MdInlineElement(
      'example',
      markers: markers,
      children: children,
      start: markers.first.start,
      end: children.last.end,
    );
  }
}

class ExampleBuilder extends MarkdownElementBuilder {
  ExampleBuilder()
      : super(
          textStyle: const TextStyle(
            color: Colors.green,
            decoration: TextDecoration.underline,
          ),
        );

  @override
  bool isBlock(element) => false;

  @override
  List<String> matchTypes = <String>['example'];
}

void main() {
  testWidgets('extension', ((tester) async {
    const data = '''
Hello **Markdown**!

---
#custom_extension
''';

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MaterialApp(
          home: MarkdownViewer(
            data,
            syntaxExtensions: [ExampleSyntax()],
            elementBuilders: [
              ExampleBuilder(),
            ],
          ),
        ),
      ),
    );

    final finder = find.descendant(
      of: find.byType(MarkdownViewer),
      matching: find.text(
        'custom_extension',
        findRichText: true,
      ),
    );
    expect(finder, findsOneWidget);
  }));
}
