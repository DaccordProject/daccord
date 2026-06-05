import 'package:bonfire/features/messaging/components/box/accord_markdown_box.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';

/// Renders message content, handling `||spoiler||` reveal-on-tap markup.
///
/// When the content has no spoiler markup it defers to [AccordMarkdownBox] so
/// the full markdown stack (bold/italic/code/links) is preserved. When spoilers
/// are present it falls back to an inline span renderer: plain-text segments are
/// rendered verbatim and spoiler segments as tappable reveal boxes. (Markdown
/// formatting inside a spoiler-containing message is not applied — matching the
/// reference client, which renders spoilers as opaque inline boxes.)
class AccordMessageContent extends StatelessWidget {
  const AccordMessageContent({super.key, required this.content});

  final String content;

  static final _spoiler = RegExp(r'\|\|(.+?)\|\|', dotAll: true);

  @override
  Widget build(BuildContext context) {
    if (!content.contains('||') || !_spoiler.hasMatch(content)) {
      return AccordMarkdownBox(content: content);
    }

    final baseStyle = Theme.of(context).textTheme.bodyLarge;
    final spans = <InlineSpan>[];
    var index = 0;
    for (final match in _spoiler.allMatches(content)) {
      if (match.start > index) {
        spans.add(TextSpan(
            text: content.substring(index, match.start), style: baseStyle));
      }
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: _Spoiler(text: match.group(1) ?? '', style: baseStyle),
      ));
      index = match.end;
    }
    if (index < content.length) {
      spans.add(TextSpan(text: content.substring(index), style: baseStyle));
    }
    return Text.rich(TextSpan(children: spans));
  }
}

class _Spoiler extends StatefulWidget {
  const _Spoiler({required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<_Spoiler> createState() => _SpoilerState();
}

class _SpoilerState extends State<_Spoiler> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return GestureDetector(
      onTap: _revealed ? null : () => setState(() => _revealed = true),
      child: MouseRegion(
        cursor:
            _revealed ? MouseCursor.defer : SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: _revealed ? Colors.transparent : colors.background,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            widget.text,
            style: (widget.style ?? const TextStyle()).copyWith(
              color: _revealed ? null : Colors.transparent,
            ),
          ),
        ),
      ),
    );
  }
}
