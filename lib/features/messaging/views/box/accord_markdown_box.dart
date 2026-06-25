import 'package:bonfire/shared/utils/platform.dart';
import 'package:bonfire/shared/utils/style/markdown/stylesheet.dart';
import 'package:dart_markdown/dart_markdown.dart' as md;
import 'package:flutter/material.dart';
import 'package:flutter_prism/flutter_prism.dart';
import 'package:markdown_viewer/markdown_viewer.dart';
import 'package:url_launcher/url_launcher.dart';

/// Renders Accord message content as markdown, reusing Bonfire's
/// `markdown_viewer` stack (stylesheet + Prism code highlighting + external
/// link launching).
///
/// Callers that render inside a space (see `AccordMessageContent`) inject
/// [syntaxExtensions] + [elementBuilders] for Accord's inline tokens — `@user`
/// / `@role` / `@everyone` / `#channel` chips, custom `:emoji:`, `||spoiler||`
/// and `__underline__` — so those render *alongside* standard markdown rather
/// than replacing it. Callers without that context (e.g. embeds) pass nothing.
class AccordMarkdownBox extends StatelessWidget {
  const AccordMarkdownBox({
    super.key,
    required this.content,
    this.syntaxExtensions = const [],
    this.elementBuilders = const [],
  });

  final String content;
  final List<md.Syntax> syntaxExtensions;
  final List<MarkdownElementBuilder> elementBuilders;

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
      syntaxExtensions: syntaxExtensions,
      elementBuilders: elementBuilders,
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
