import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:markdown_viewer/markdown_viewer.dart';

MarkdownStyle getMarkdownStyleSheet(BuildContext context) {
  // Body text follows the theme's high-emphasis colour, like the rest of the
  // app's typography. It was hard-coded to #EBEBEB, which is ~1:1 on the Light
  // theme's background and left message text effectively invisible.
  final textColor = BonfireThemeExtension.of(context).dirtyWhite;
  return MarkdownStyle(
    paragraph: TextStyle(
      fontSize: 14.5,
      fontWeight: FontWeight.w400,
      color: textColor,
    ),
    codeBlock: const TextStyle(fontFamily: 'monospace', fontSize: 14),
    codeblockDecoration: BoxDecoration(
      color: BonfireThemeExtension.of(context).foreground,
      borderRadius: BorderRadius.circular(8),
    ),
    codeSpan: TextStyle(
      fontFamily: 'monospace',
      backgroundColor: BonfireThemeExtension.of(context).foreground,
      fontSize: 14,
    ),
    list: TextStyle(
      fontSize: 14.5,
      fontWeight: FontWeight.w500,
      color: textColor,
    ),
    listItem: TextStyle(
      fontSize: 14.5,
      fontWeight: FontWeight.w500,
      color: textColor,
    ),
    headline1: TextStyle(
      fontSize: 30,
      fontWeight: FontWeight.bold,
      color: textColor,
    ),
    headline2: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.bold,
      color: textColor,
    ),
    headline3: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.bold,
      color: textColor,
    ),
    headline4: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.bold,
      color: textColor,
    ),
    headline5: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.bold,
      color: textColor,
    ),
    headline6: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.bold,
      color: textColor,
    ),
  );
}
