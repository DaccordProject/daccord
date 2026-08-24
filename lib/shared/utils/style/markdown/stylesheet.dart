import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:markdown_viewer/markdown_viewer.dart';

MarkdownStyle getMarkdownStyleSheet(BuildContext context) {
  const textColor = Color.fromARGB(255, 235, 235, 235);
  return MarkdownStyle(
    paragraph: const TextStyle(
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
