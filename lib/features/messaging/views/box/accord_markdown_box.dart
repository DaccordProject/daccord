import 'package:bonfire/features/messaging/views/message_media_gate.dart';
import 'package:bonfire/shared/utils/external_url.dart';
import 'package:bonfire/shared/utils/platform.dart';
import 'package:bonfire/shared/utils/style/markdown/stylesheet.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dart_markdown/dart_markdown.dart' as md;
import 'package:flutter/material.dart';
import 'package:flutter_prism/flutter_prism.dart';
import 'package:markdown_viewer/markdown_viewer.dart';

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
    this.trustedMediaBaseUrl,
    this.syntaxExtensions = const [],
    this.elementBuilders = const [],
  });

  final String content;
  final String? trustedMediaBaseUrl;
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
      imageBuilder: (uri, info) => MessageMediaGate(
        source: uri.toString(),
        trustedBaseUrl: trustedMediaBaseUrl,
        blockedPlaceholder: Text(info.description ?? ''),
        builder: (_, url) => CachedNetworkImage(
          imageUrl: url,
          width: info.width,
          height: info.height,
          errorWidget: (_, _, _) => Text(info.description ?? ''),
        ),
      ),
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
      onTapLink: (href, title) async {
        if (href == null) return;
        await openExternalUrl(context, href);
      },
    );
  }
}
