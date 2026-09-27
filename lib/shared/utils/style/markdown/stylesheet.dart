import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_prism/flutter_prism.dart';
import 'package:markdown_viewer/markdown_viewer.dart';

MarkdownStyle getMarkdownStyleSheet(BuildContext context) {
  final palette = BonfireThemeExtension.of(context);
  const textColor = Color.fromARGB(255, 235, 235, 235);
  final codeStyle = TextStyle(
    fontFamily: 'monospace',
    fontSize: 14.5,
    fontWeight: FontWeight.w500,
    color: palette.dirtyWhite,
  );
  return MarkdownStyle(
    paragraph: const TextStyle(
      fontSize: 14.5,
      fontWeight: FontWeight.w400,
      color: textColor,
    ),
    codeBlock: codeStyle.copyWith(height: 1.5),
    codeblockDecoration: BoxDecoration(
      color: palette.foreground,
      borderRadius: BorderRadius.circular(8),
    ),
    codeSpan: codeStyle.copyWith(backgroundColor: palette.foreground),
    list: const TextStyle(
      fontSize: 14.5,
      fontWeight: FontWeight.w500,
      color: textColor,
    ),
    listItem: const TextStyle(
      fontSize: 14.5,
      fontWeight: FontWeight.w500,
      color: textColor,
    ),
    headline1: const TextStyle(
      fontSize: 30,
      fontWeight: FontWeight.bold,
      color: textColor,
    ),
    headline2: const TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.bold,
      color: textColor,
    ),
    headline3: const TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.bold,
      color: textColor,
    ),
    headline4: const TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.bold,
      color: textColor,
    ),
    headline5: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.bold,
      color: textColor,
    ),
    headline6: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.bold,
      color: textColor,
    ),
  );
}

/// Syntax colors with at least 4.5:1 contrast on each preset's code surface.
PrismStyle getMarkdownPrismStyle(BuildContext context) {
  final palette = BonfireThemeExtension.of(context);
  final dark = Theme.of(context).brightness == Brightness.dark;
  final text = TextStyle(color: palette.dirtyWhite);
  final comment = TextStyle(color: palette.gray);
  final purple = TextStyle(
    color: dark ? const Color(0xFFC4B5FD) : const Color(0xFF6D28D9),
  );
  final cyan = TextStyle(
    color: dark ? const Color(0xFF8BD5E5) : const Color(0xFF086779),
  );
  final green = TextStyle(
    color: dark ? const Color(0xFFA6DA95) : const Color(0xFF356A24),
  );
  final orange = TextStyle(
    color: dark ? const Color(0xFFF5C285) : const Color(0xFF925000),
  );
  final red = TextStyle(
    color: dark ? const Color(0xFFF5A0A9) : const Color(0xFFA1263D),
  );
  return PrismStyle(
    token: text,
    atrule: purple,
    attrName: cyan,
    attrValue: green,
    boolean: purple,
    builtin: cyan,
    cdata: comment,
    char: green,
    className: cyan,
    comment: comment,
    constant: purple,
    deleted: red,
    doctype: comment,
    entity: orange,
    function: orange,
    important: purple.copyWith(fontWeight: FontWeight.bold),
    inserted: green,
    keyword: purple,
    namespace: text,
    number: orange,
    operator: cyan,
    prolog: comment,
    property: cyan,
    punctuation: text,
    regex: orange,
    selector: green,
    string: green,
    symbol: purple,
    tag: red,
    url: cyan,
  );
}
