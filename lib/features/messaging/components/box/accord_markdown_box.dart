import 'package:bonfire/shared/utils/platform.dart';
import 'package:bonfire/shared/utils/style/markdown/stylesheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_prism/flutter_prism.dart';
import 'package:markdown_viewer/markdown_viewer.dart';
import 'package:url_launcher/url_launcher.dart';

/// Renders Accord message content as markdown, reusing Bonfire's
/// `markdown_viewer` stack (stylesheet + Prism code highlighting + external
/// link launching). Unlike the firebridge `MessageMarkdownBox`, it takes a
/// plain content string and omits the Discord-coupled mention extensions
/// (`<@id>` / `<#id>` resolution against guild providers); Accord mention
/// rendering is a separate follow-up.
class AccordMarkdownBox extends StatelessWidget {
  const AccordMarkdownBox({super.key, required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    return MarkdownViewer(
      content,
      enableTaskList: true,
      enableSuperscript: false,
      enableSubscript: false,
      enableFootnote: false,
      enableImageSize: false,
      selectable: shouldUseDesktopLayout(context),
      enableKbd: false,
      styleSheet: getMarkdownStyleSheet(context),
      highlightBuilder: (text, language, infoString) {
        final prism = Prism(
          style: Theme.of(context).brightness == Brightness.dark
              ? const PrismStyle.dark()
              : const PrismStyle(),
        );
        try {
          return prism.render(text, language ?? 'plain');
        } catch (e) {
          debugPrint('AccordMarkdownBox: highlightBuilder error: $e');
          return <TextSpan>[TextSpan(text: text)];
        }
      },
      onTapLink: (href, title) {
        if (href == null) return;
        launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
      },
    );
  }
}
