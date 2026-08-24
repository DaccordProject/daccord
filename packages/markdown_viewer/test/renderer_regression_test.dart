import 'dart:convert';

import 'package:dart_markdown/dart_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_viewer/markdown_viewer.dart';
import 'package:markdown_viewer/src/extensions.dart';

void main() {
  test('soft line endings render as spaces', () {
    final rendered = _render('first\nsecond');

    expect(_textValues(rendered), contains('first second'));
  });

  test('code blocks preserve line endings', () {
    final rendered = _render('```\nfirst\nsecond\n```');

    expect(_textValues(rendered), contains('first\nsecond'));
  });

  test('GFM tables populate every row with mutable cells', () {
    final rendered = _render('| a | b |\n| - | - |\n| c | d |');
    final serialized = jsonEncode(rendered);

    expect(RegExp('"type":"TableRow"').allMatches(serialized), hasLength(2));
    expect(RegExp('"type":"TableCell"').allMatches(serialized), hasLength(4));
  });
}

List<Map<String, dynamic>> _render(String markdown) {
  final nodes = Markdown(
    enableHtmlBlock: false,
    enableRawHtml: false,
    enableHighlight: true,
    enableStrikethrough: true,
  ).parse(markdown);

  return MarkdownRenderer(
    styleSheet: const MarkdownStyle(),
  ).render(nodes).map((widget) => widget.toMap()).toList();
}

Iterable<String> _textValues(Object? value) sync* {
  if (value is Map) {
    final text = value['text'];
    if (text is String) yield text;
    for (final child in value.values) {
      yield* _textValues(child);
    }
  } else if (value is Iterable) {
    for (final child in value) {
      yield* _textValues(child);
    }
  }
}
