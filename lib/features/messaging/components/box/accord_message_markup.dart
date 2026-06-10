import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dart_markdown/dart_markdown.dart' as md;
import 'package:flutter/material.dart';
import 'package:markdown_viewer/markdown_viewer.dart';
import 'package:source_span/source_span.dart';

/// Custom markdown markup for Accord messages: inline `@user` / `@role` /
/// `@everyone` / `#channel` chips, custom `:emoji:`, `||spoiler||` reveals, and
/// Daccord `__underline__`.
///
/// These plug into [MarkdownViewer] as `syntaxExtensions` + `elementBuilders`,
/// so a message renders standard markdown (bold/italic/code/links/lists) AND
/// these Accord tokens together — rather than the old all-or-nothing split where
/// any chip disabled markdown for the whole message.
///
/// Build the pair via [buildAccordMarkup]; resolution data (member/role/channel
/// lookups, custom emoji, cdn url) and tap callbacks are captured up front by
/// the caller so the syntaxes and builders stay context-free.

const _mentionColor = Color(0xFF5865F2);
const _broadcastColor = Color(0xFFFAA61A);

/// Lowercase-keyed lookups + tap handlers used to resolve and wire chips.
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

  /// Members keyed by lowercased username *and* display name.
  final Map<String, AccordMember> userByHandle;

  /// Mentionable roles keyed by lowercased name.
  final Map<String, AccordRole> roleByName;

  /// Non-category channels keyed by lowercased name.
  final Map<String, AccordChannel> channelByName;

  /// Custom space emoji keyed by lowercased shortcode name.
  final Map<String, AccordEmoji> emojiByName;

  final String? cdnUrl;

  /// Opens the profile popout for a mentioned user.
  final void Function(String userId)? onTapUser;

  /// Opens (or switches to) the tab for a mentioned channel.
  final void Function(String channelId)? onTapChannel;
}

/// Returns the `(syntaxExtensions, elementBuilders)` to hand to [MarkdownViewer]
/// for [ctx]. Returns empty lists when there is nothing to resolve against, so
/// callers can skip the custom pipeline entirely.
({List<md.Syntax> syntaxes, List<MarkdownElementBuilder> builders})
buildAccordMarkup(AccordMarkupContext ctx) {
  final syntaxes = <md.Syntax>[
    _MentionSyntax(ctx),
    _ChannelSyntax(ctx),
    _EmojiSyntax(ctx),
    _SpoilerSyntax(),
    _UnderlineSyntax(),
  ];
  final builders = <MarkdownElementBuilder>[
    _MentionBuilder(ctx),
    _ChannelBuilder(ctx),
    _EmojiBuilder(),
    _SpoilerBuilder(),
    _UnderlineBuilder(),
  ];
  return (syntaxes: syntaxes, builders: builders);
}

// ---------------------------------------------------------------------------
// Syntaxes
// ---------------------------------------------------------------------------

bool _isWordChar(int c) {
  if (c >= 0x30 && c <= 0x39) return true; // 0-9
  if (c >= 0x41 && c <= 0x5A) return true; // A-Z
  if (c >= 0x61 && c <= 0x7A) return true; // a-z
  if (c == 0x5F) return true; // _
  return c > 0x7F; // non-ASCII (treat as word char)
}

md.InlineElement _leaf(
  String type,
  List<SourceSpan> markers,
  Map<String, String> attributes,
) =>
    md.InlineElement(
      type,
      markers: markers,
      attributes: attributes,
      start: markers.first.start,
      end: markers.last.end,
    );

/// `@everyone`, `@here`, or `@username`/`@displayname`/`@rolename`. Only emits a
/// chip when it resolves to a real broadcast/member/role; otherwise leaves the
/// text alone (so `email@host` and unknown handles stay plain).
class _MentionSyntax extends md.InlineSyntax {
  _MentionSyntax(this.ctx)
      : super(RegExp(r'@(everyone|here)\b|@(\w+)'));

  final AccordMarkupContext ctx;

  @override
  md.InlineElement? parse(md.InlineParser parser, Match match) {
    // Require the char before `@` (if any) to be a non-word char, so we don't
    // chip up the back half of things like `email@host`.
    final pos = parser.position;
    if (pos > 0 && _isWordChar(parser.charAt(pos - 1))) return null;

    final broadcast = match[1];
    final handle = match[2];
    Map<String, String>? attrs;
    if (broadcast != null) {
      attrs = {'kind': 'broadcast', 'label': '@$broadcast'};
    } else if (handle != null) {
      final lower = handle.toLowerCase();
      final role = ctx.roleByName[lower];
      if (role != null) {
        attrs = {
          'kind': 'role',
          'label': '@${role.name}',
          'roleColor': '${role.color}',
        };
      } else {
        final member = ctx.userByHandle[lower];
        if (member != null) {
          attrs = {
            'kind': 'user',
            'label': '@${accordMemberName(member, fallback: handle)}',
            if (member.user?.id != null) 'userId': member.user!.id,
          };
        }
      }
    }
    if (attrs == null) return null;

    final markers = parser.consumeBy(match[0]!.length);
    return _leaf('accordMention', markers, attrs);
  }
}

/// `#channel-name` → chip when it resolves to a non-category channel.
class _ChannelSyntax extends md.InlineSyntax {
  _ChannelSyntax(this.ctx) : super(RegExp(r'#([A-Za-z0-9_\-]+)'));

  final AccordMarkupContext ctx;

  @override
  md.InlineElement? parse(md.InlineParser parser, Match match) {
    final name = match[1];
    if (name == null) return null;
    final channel = ctx.channelByName[name.toLowerCase()];
    if (channel == null) return null;

    final markers = parser.consumeBy(match[0]!.length);
    return _leaf('accordChannel', markers, {
      'label': '#${channel.name}',
      'channelId': channel.id,
    });
  }
}

/// `:shortcode:` → custom space emoji image when it resolves.
class _EmojiSyntax extends md.InlineSyntax {
  _EmojiSyntax(this.ctx) : super(RegExp(r':([A-Za-z0-9_]+):'));

  final AccordMarkupContext ctx;

  @override
  md.InlineElement? parse(md.InlineParser parser, Match match) {
    final name = match[1];
    if (name == null) return null;
    final emoji = ctx.emojiByName[name.toLowerCase()];
    if (emoji == null) return null;
    final url = _emojiImageUrl(emoji, ctx.cdnUrl);
    if (url == null) return null;

    final markers = parser.consumeBy(match[0]!.length);
    return _leaf('accordEmoji', markers, {'url': url, 'name': name});
  }
}

/// `||spoiler||` → tap-to-reveal box. Inner content is rendered as plain text.
class _SpoilerSyntax extends md.InlineSyntax {
  _SpoilerSyntax() : super(RegExp(r'\|\|(.+?)\|\|', dotAll: true));

  @override
  md.InlineElement? parse(md.InlineParser parser, Match match) {
    final markers = parser.consumeBy(match[0]!.length);
    return _leaf('accordSpoiler', markers, {'text': match[1] ?? ''});
  }
}

/// Daccord `__text__` underline (the reference maps `__` to underline, not the
/// CommonMark strong emphasis). Registered ahead of the built-in underscore
/// emphasis so it wins.
class _UnderlineSyntax extends md.InlineSyntax {
  _UnderlineSyntax() : super(RegExp(r'__(.+?)__', dotAll: true));

  @override
  md.InlineElement? parse(md.InlineParser parser, Match match) {
    final length = match[0]!.length;
    final open = parser.consumeBy(2);
    final content = parser.consumeBy(length - 4);
    final close = parser.consumeBy(2);
    return md.InlineElement(
      'accordUnderline',
      markers: [...open, ...close],
      children: content.map<md.InlineObject>(md.Text.fromSpan).toList(),
      start: open.first.start,
      end: close.last.end,
    );
  }
}

// ---------------------------------------------------------------------------
// Builders
// ---------------------------------------------------------------------------

String? _emojiImageUrl(AccordEmoji emoji, String? cdnUrl) {
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

/// Wraps [child] as an inline widget. The root span is a [WidgetSpan] so the
/// renderer keeps it as a discrete inline item instead of trying to merge it
/// into an adjacent text run.
RichText _inlineWidget(Widget child) => RichText(
      text: WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        baseline: TextBaseline.alphabetic,
        child: child,
      ),
    );

class _MentionBuilder extends MarkdownElementBuilder {
  _MentionBuilder(this.ctx);

  final AccordMarkupContext ctx;

  @override
  final matchTypes = const ['accordMention'];

  @override
  bool isBlock(element) => false;

  @override
  Widget? buildWidget(element, parent) {
    final a = element.attributes;
    final kind = a['kind'];
    final color = switch (kind) {
      'broadcast' => _broadcastColor,
      'role' =>
        accordRoleColor(int.tryParse(a['roleColor'] ?? '') ?? 0) ??
            _mentionColor,
      _ => _mentionColor,
    };
    final userId = a['userId'];
    return _inlineWidget(
      _Chip(
        label: a['label'] ?? '',
        color: color,
        onTap: userId != null && ctx.onTapUser != null
            ? () => ctx.onTapUser!(userId)
            : null,
      ),
    );
  }
}

class _ChannelBuilder extends MarkdownElementBuilder {
  _ChannelBuilder(this.ctx);

  final AccordMarkupContext ctx;

  @override
  final matchTypes = const ['accordChannel'];

  @override
  bool isBlock(element) => false;

  @override
  Widget? buildWidget(element, parent) {
    final a = element.attributes;
    final channelId = a['channelId'];
    return _inlineWidget(
      _Chip(
        label: a['label'] ?? '',
        color: _mentionColor,
        onTap: channelId != null && ctx.onTapChannel != null
            ? () => ctx.onTapChannel!(channelId)
            : null,
      ),
    );
  }
}

class _EmojiBuilder extends MarkdownElementBuilder {
  @override
  final matchTypes = const ['accordEmoji'];

  @override
  bool isBlock(element) => false;

  @override
  Widget? buildWidget(element, parent) {
    final a = element.attributes;
    return _inlineWidget(
      _EmojiImage(url: a['url'], name: a['name'] ?? ''),
    );
  }
}

class _SpoilerBuilder extends MarkdownElementBuilder {
  @override
  final matchTypes = const ['accordSpoiler'];

  @override
  bool isBlock(element) => false;

  @override
  Widget? buildWidget(element, parent) {
    return _inlineWidget(
      _Spoiler(text: element.attributes['text'] ?? '', style: parent.style),
    );
  }
}

class _UnderlineBuilder extends MarkdownElementBuilder {
  _UnderlineBuilder()
      : super(textStyle: const TextStyle(decoration: TextDecoration.underline));

  @override
  final matchTypes = const ['accordUnderline'];

  @override
  bool isBlock(element) => false;
}

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

/// A styled mention/channel pill. Tappable when [onTap] is provided.
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
        cursor: _revealed ? MouseCursor.defer : SystemMouseCursors.click,
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
