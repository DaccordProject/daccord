import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dart_markdown/dart_markdown.dart' as md;
import 'package:flutter/material.dart';
import 'package:markdown_viewer/markdown_viewer.dart';

/// Resolved lookup tables + tap callbacks for rendering Accord's inline tokens
/// (`@user` / `@role` / `@everyone` / `#channel` chips, custom `:emoji:`,
/// `||spoiler||`, `__underline__`) as markdown syntax extensions.
///
/// All maps are keyed by the **lowercased** handle/name so resolution is
/// case-insensitive. Anything not present here simply renders as plain text —
/// an unresolved `#channel` or `@user` is left verbatim rather than chipped.
/// Pass empty maps (the default) in contexts without a space (e.g. DMs); the
/// protocol-agnostic tokens (`@everyone`/`@here`, spoiler, underline, markdown)
/// still apply.
class AccordMarkupContext {
  const AccordMarkupContext({
    this.userByHandle = const {},
    this.roleByName = const {},
    this.channelByName = const {},
    this.emojiByName = const {},
    this.cdnUrl,
    this.onTapUser,
    this.onTapChannel,
  });

  final Map<String, AccordMember> userByHandle;
  final Map<String, AccordRole> roleByName;
  final Map<String, AccordChannel> channelByName;
  final Map<String, AccordEmoji> emojiByName;
  final String? cdnUrl;
  final void Function(String userId)? onTapUser;
  final void Function(String channelId)? onTapChannel;
}

/// Builds the syntax extensions + element builders that teach
/// [AccordMarkdownBox]'s `markdown_viewer` stack to render Accord's inline
/// tokens *alongside* standard markdown (rather than replacing it).
///
/// Custom inline syntaxes are evaluated before the built-in emphasis syntaxes,
/// so `__text__` becomes an underline (matching the reference client) instead
/// of bold, and `:emoji:` / `@mention` / `#channel` chip up when they resolve.
({List<md.Syntax> syntaxes, List<MarkdownElementBuilder> builders})
buildAccordMarkup(AccordMarkupContext ctx) {
  return (
    syntaxes: <md.Syntax>[
      _SpoilerSyntax(),
      _UnderlineSyntax(),
      _EmojiSyntax(ctx),
      _MentionSyntax(ctx),
      _ChannelSyntax(ctx),
    ],
    builders: <MarkdownElementBuilder>[
      _SpoilerBuilder(),
      _UnderlineBuilder(),
      _EmojiBuilder(),
      _MentionBuilder(ctx.onTapUser),
      _ChannelBuilder(ctx.onTapChannel),
    ],
  );
}

// ---------------------------------------------------------------------------
// Syntaxes
// ---------------------------------------------------------------------------

/// `||text||` → an `accordSpoiler` element carrying the hidden text.
class _SpoilerSyntax extends md.InlineSyntax {
  _SpoilerSyntax() : super(RegExp(r'\|\|(.+?)\|\|', dotAll: true));

  @override
  md.InlineObject? parse(md.InlineParser parser, Match match) {
    final markers = parser.consumeBy(match[0]!.length);
    return md.InlineElement(
      'accordSpoiler',
      markers: markers,
      attributes: {'text': match[1] ?? ''},
      start: markers.first.start,
      end: markers.last.end,
    );
  }
}

/// `__text__` → an `accordUnderline` element. Unlike standard markdown (which
/// treats `__` as bold) the reference client maps this to an underline. The
/// inner text is preserved as a child [md.Text] so it renders with the parent
/// style merged.
class _UnderlineSyntax extends md.InlineSyntax {
  _UnderlineSyntax() : super(RegExp(r'__(.+?)__', dotAll: true));

  @override
  md.InlineObject? parse(md.InlineParser parser, Match match) {
    final start = parser.position;
    final full = match[0]!;
    final innerSpans = parser.subspan(start + 2, start + full.length - 2);
    final markers = parser.consumeBy(full.length);
    return md.InlineElement(
      'accordUnderline',
      markers: markers,
      children: innerSpans
          .map<md.InlineObject>((span) => md.Text.fromSpan(span))
          .toList(),
      start: markers.first.start,
      end: markers.last.end,
    );
  }
}

/// `:name:` → an `accordEmoji` element, but only when the name resolves to a
/// space emoji. Otherwise it regrets the match (returns `null` without
/// consuming) so the literal `:name:` is left for other syntaxes / plain text.
class _EmojiSyntax extends md.InlineSyntax {
  _EmojiSyntax(this.ctx) : super(RegExp(r':([A-Za-z0-9_]+):'));

  final AccordMarkupContext ctx;

  @override
  md.InlineObject? parse(md.InlineParser parser, Match match) {
    final emoji = ctx.emojiByName[match[1]!.toLowerCase()];
    if (emoji == null) return null;
    final url = _emojiUrl(emoji, ctx.cdnUrl);
    final markers = parser.consumeBy(match[0]!.length);
    return md.InlineElement(
      'accordEmoji',
      markers: markers,
      attributes: {'name': match[1]!, if (url != null) 'url': url},
      start: markers.first.start,
      end: markers.last.end,
    );
  }
}

/// `@everyone` / `@here` / `@handle` → an `accordMention` chip. `@everyone` and
/// `@here` always chip up; a `@handle` chips only when it resolves to a
/// mentionable role or a member (else it regrets). A leading word character
/// (e.g. the `@` in `email@host`) suppresses the match.
class _MentionSyntax extends md.InlineSyntax {
  _MentionSyntax(this.ctx) : super(RegExp(r'@(everyone|here)\b|@(\w+)'));

  final AccordMarkupContext ctx;

  @override
  md.InlineObject? parse(md.InlineParser parser, Match match) {
    final pos = parser.position;
    if (pos > 0 && _isWordCharCode(parser.charAt(pos - 1))) return null;

    String label;
    Color color;
    String? userId;

    final broadcast = match[1];
    if (broadcast != null) {
      label = '@$broadcast';
      color = _broadcastColor;
    } else {
      final handle = match[2]!;
      final lower = handle.toLowerCase();
      final role = ctx.roleByName[lower];
      if (role != null) {
        label = '@${role.name}';
        color = accordRoleColor(role.color) ?? _mentionColor;
      } else {
        final member = ctx.userByHandle[lower];
        if (member == null) return null;
        label = '@${_memberLabel(member, handle)}';
        color = _mentionColor;
        userId = member.user?.id;
      }
    }

    final markers = parser.consumeBy(match[0]!.length);
    return md.InlineElement(
      'accordMention',
      markers: markers,
      attributes: {
        'label': label,
        'color': _encodeColor(color),
        if (userId != null) 'userId': userId,
      },
      start: markers.first.start,
      end: markers.last.end,
    );
  }
}

/// `#name` → an `accordChannel` chip, only when it resolves to a real channel
/// (else it regrets). A leading word character suppresses the match.
class _ChannelSyntax extends md.InlineSyntax {
  _ChannelSyntax(this.ctx) : super(RegExp(r'#([A-Za-z0-9_\-]+)'));

  final AccordMarkupContext ctx;

  @override
  md.InlineObject? parse(md.InlineParser parser, Match match) {
    final pos = parser.position;
    if (pos > 0 && _isWordCharCode(parser.charAt(pos - 1))) return null;

    final channel = ctx.channelByName[match[1]!.toLowerCase()];
    if (channel == null) return null;

    final markers = parser.consumeBy(match[0]!.length);
    return md.InlineElement(
      'accordChannel',
      markers: markers,
      attributes: {
        'label': '#${channel.name}',
        'color': _encodeColor(_mentionColor),
        'channelId': channel.id,
      },
      start: markers.first.start,
      end: markers.last.end,
    );
  }
}

// ---------------------------------------------------------------------------
// Builders
// ---------------------------------------------------------------------------

class _MentionBuilder extends MarkdownElementBuilder {
  _MentionBuilder(this.onTapUser);

  final void Function(String userId)? onTapUser;

  @override
  List<String> get matchTypes => const ['accordMention'];

  @override
  bool isBlock(element) => false;

  @override
  Widget? buildWidget(element, parent) {
    final a = element.attributes;
    final userId = a['userId'];
    final tap = (userId != null && onTapUser != null)
        ? () => onTapUser!(userId)
        : null;
    return _inlineWidget(
      _Chip(label: a['label'] ?? '', color: _decodeColor(a['color']), onTap: tap),
    );
  }
}

class _ChannelBuilder extends MarkdownElementBuilder {
  _ChannelBuilder(this.onTapChannel);

  final void Function(String channelId)? onTapChannel;

  @override
  List<String> get matchTypes => const ['accordChannel'];

  @override
  bool isBlock(element) => false;

  @override
  Widget? buildWidget(element, parent) {
    final a = element.attributes;
    final channelId = a['channelId'];
    final tap = (channelId != null && onTapChannel != null)
        ? () => onTapChannel!(channelId)
        : null;
    return _inlineWidget(
      _Chip(label: a['label'] ?? '', color: _decodeColor(a['color']), onTap: tap),
    );
  }
}

class _EmojiBuilder extends MarkdownElementBuilder {
  @override
  List<String> get matchTypes => const ['accordEmoji'];

  @override
  bool isBlock(element) => false;

  @override
  Widget? buildWidget(element, parent) {
    final a = element.attributes;
    return _inlineWidget(_EmojiImage(url: a['url'], name: a['name'] ?? ''));
  }
}

class _SpoilerBuilder extends MarkdownElementBuilder {
  @override
  List<String> get matchTypes => const ['accordSpoiler'];

  @override
  bool isBlock(element) => false;

  @override
  Widget? buildWidget(element, parent) {
    return _inlineWidget(_Spoiler(text: element.attributes['text'] ?? ''));
  }
}

/// Underline relies on the default (children-merging) [buildWidget]; supplying
/// a [textStyle] with an underline decoration is enough.
class _UnderlineBuilder extends MarkdownElementBuilder {
  _UnderlineBuilder()
      : super(textStyle: const TextStyle(decoration: TextDecoration.underline));

  @override
  List<String> get matchTypes => const ['accordUnderline'];
}

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

/// Wraps an arbitrary [child] widget into a [RichText] whose root span is a
/// [WidgetSpan]. The renderer only permits `RichText`/`Text`/`DefaultTextStyle`
/// /`Consumer` from an inline `buildWidget`; returning the widget *inside* a
/// `RichText` (with a `WidgetSpan` root) keeps it a discrete inline item — the
/// merge pass detects the `WidgetSpan` and lays these out in a `Wrap` rather
/// than trying to cast it into a `List<TextSpan>` (which would throw).
Widget _inlineWidget(Widget child) => RichText(
      text: WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: child,
      ),
    );

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color, this.onTap});

  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
    if (onTap == null) return chip;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: chip),
    );
  }
}

/// An inline custom-emoji image (~20px). Falls back to the literal `:name:`
/// text when there's no URL or the image fails to load.
class _EmojiImage extends StatelessWidget {
  const _EmojiImage({required this.url, required this.name});

  final String? url;
  final String name;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return Text(':$name:', style: Theme.of(context).textTheme.bodyLarge);
    }
    return Tooltip(
      message: ':$name:',
      child: CachedNetworkImage(
        imageUrl: url!,
        width: 20,
        height: 20,
        fit: BoxFit.contain,
        errorWidget: (context, _, _) =>
            Text(':$name:', style: Theme.of(context).textTheme.bodyLarge),
      ),
    );
  }
}

class _Spoiler extends StatefulWidget {
  const _Spoiler({required this.text});

  final String text;

  @override
  State<_Spoiler> createState() => _SpoilerState();
}

class _SpoilerState extends State<_Spoiler> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final style = Theme.of(context).textTheme.bodyLarge;
    return GestureDetector(
      onTap: _revealed ? null : () => setState(() => _revealed = true),
      child: MouseRegion(
        cursor: _revealed ? MouseCursor.defer : SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: _revealed ? Colors.transparent : colors.background,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            widget.text,
            style: (style ?? const TextStyle()).copyWith(
              color: _revealed ? null : Colors.transparent,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _mentionColor = Color(0xFF5865F2);
const _broadcastColor = Color(0xFFFAA61A);

String _encodeColor(Color color) => color.toARGB32().toString();

Color _decodeColor(String? encoded) {
  if (encoded == null) return _mentionColor;
  return Color(int.tryParse(encoded) ?? _mentionColor.toARGB32());
}

String _memberLabel(AccordMember member, String fallback) {
  final display = member.user?.displayName;
  if (display != null && display.isNotEmpty) return display;
  final username = member.user?.username;
  if (username != null && username.isNotEmpty) return username;
  return fallback;
}

/// Resolves [emoji] to an absolute image URL (mirrors the emoji picker): an
/// explicit `imageUrl` wins, else the CDN path by id. Null when neither.
String? _emojiUrl(AccordEmoji emoji, String? cdnUrl) {
  if (emoji.imageUrl.isNotEmpty) {
    return AccordCDN.resolvePath(emoji.imageUrl, cdnUrl: cdnUrl ?? '');
  }
  final id = emoji.id;
  if (id == null) return null;
  return AccordCDN.emoji(
    id,
    format: emoji.animated ? 'gif' : 'png',
    cdnUrl: cdnUrl ?? '',
  );
}

bool _isWordCharCode(int c) {
  if (c >= 0x30 && c <= 0x39) return true; // 0-9
  if (c >= 0x41 && c <= 0x5A) return true; // A-Z
  if (c >= 0x61 && c <= 0x7A) return true; // a-z
  if (c == 0x5F) return true; // _
  return c > 0x7F; // non-ASCII (treat as word char)
}
