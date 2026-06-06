import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/messaging/components/box/accord_markdown_box.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Renders message content with `||spoiler||` reveal-on-tap markup and inline
/// chips for `@user`, `@role`, `@everyone`/`@here`, and `#channel` references.
///
/// When the content has no spoilers and no chip-eligible references it defers
/// to [AccordMarkdownBox] so the full markdown stack (bold/italic/code/links)
/// is preserved. When either is present it falls back to an inline span
/// renderer: plain text segments are rendered verbatim, spoilers as tappable
/// reveal boxes, and mentions/channels as styled chips. (Markdown formatting
/// inside a chip-containing message is not applied — matching the existing
/// spoiler behaviour, and the reference client which renders these as inline
/// pills, not formatted markup.)
///
/// Pass [spaceId] when rendering inside a space so user/role/channel handles
/// resolve against the space's caches; without it, only `@everyone`/`@here`
/// chip up (suitable for DMs).
class AccordMessageContent extends ConsumerWidget {
  const AccordMessageContent({super.key, required this.content, this.spaceId});

  final String content;
  final String? spaceId;

  static final _spoiler = RegExp(r'\|\|(.+?)\|\|', dotAll: true);

  /// Matches `@everyone`, `@here`, `@<word>`, or `#<word-or-hyphen>`. The
  /// capture groups distinguish the kind, and `\B@` would over-match inside
  /// words like `email@host`, so we require the previous character (if any) to
  /// be a non-word char via a manual check at match time.
  static final _chip = RegExp(r'@(everyone|here)\b|@(\w+)|#([A-Za-z0-9_\-]+)');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasSpoiler = content.contains('||') && _spoiler.hasMatch(content);
    final hasChip = _chip.hasMatch(content);
    if (!hasSpoiler && !hasChip) {
      return AccordMarkdownBox(content: content);
    }

    final members = spaceId == null
        ? null
        : ref.watch(accordMembersControllerProvider(spaceId!));
    final space = spaceId == null
        ? null
        : ref.watch(spacesControllerProvider
            .select((s) => s?.firstWhereOrNull((sp) => sp.id == spaceId)));
    final channels = spaceId == null
        ? null
        : ref.watch(accordChannelsControllerProvider(spaceId!));
    final roles = space?.roles ?? const <AccordRole>[];

    final baseStyle = Theme.of(context).textTheme.bodyLarge;
    final spans = <InlineSpan>[];

    // First split by spoiler matches so chip detection runs only over plain
    // segments — chips inside spoilers stay opaque under the reveal box.
    int cursor = 0;
    for (final spoiler in _spoiler.allMatches(content)) {
      if (spoiler.start > cursor) {
        _appendTextWithChips(
          context: context,
          text: content.substring(cursor, spoiler.start),
          baseStyle: baseStyle,
          spans: spans,
          members: members,
          roles: roles,
          channels: channels,
        );
      }
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: _Spoiler(text: spoiler.group(1) ?? '', style: baseStyle),
      ));
      cursor = spoiler.end;
    }
    if (cursor < content.length) {
      _appendTextWithChips(
        context: context,
        text: content.substring(cursor),
        baseStyle: baseStyle,
        spans: spans,
        members: members,
        roles: roles,
        channels: channels,
      );
    }
    return Text.rich(TextSpan(children: spans));
  }

  /// Appends [text] to [spans], substituting [_chip]-matching references with
  /// styled WidgetSpan chips. A reference renders as a chip only when it
  /// resolves to a real member/role/channel (or is `@everyone`/`@here`);
  /// anything else falls through as plain text so we don't chip up arbitrary
  /// `@words` or `#hashtags`.
  void _appendTextWithChips({
    required BuildContext context,
    required String text,
    required TextStyle? baseStyle,
    required List<InlineSpan> spans,
    required Map<String, AccordMember>? members,
    required List<AccordRole> roles,
    required List<AccordChannel>? channels,
  }) {
    int cursor = 0;
    for (final match in _chip.allMatches(text)) {
      // Don't chip up `email@host` etc. — require the previous char (if any)
      // to be a non-word boundary.
      if (match.start > 0 && _isWordChar(text[match.start - 1])) {
        continue;
      }
      final chip = _resolveChip(match, members, roles, channels);
      if (chip == null) continue;
      if (match.start > cursor) {
        spans.add(TextSpan(
            text: text.substring(cursor, match.start), style: baseStyle));
      }
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: _Chip(label: chip.label, color: chip.color),
      ));
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans
          .add(TextSpan(text: text.substring(cursor), style: baseStyle));
    }
  }

  _ChipData? _resolveChip(
    RegExpMatch match,
    Map<String, AccordMember>? members,
    List<AccordRole> roles,
    List<AccordChannel>? channels,
  ) {
    final broadcast = match.group(1);
    if (broadcast != null) {
      // `@everyone`/`@here`: always chip up.
      return _ChipData(label: '@$broadcast', color: _broadcastColor);
    }
    final userHandle = match.group(2);
    if (userHandle != null) {
      final lower = userHandle.toLowerCase();
      // Try role first (more specific) then member username/display.
      final role = roles.firstWhereOrNull(
          (r) => r.mentionable && r.name.toLowerCase() == lower);
      if (role != null) {
        return _ChipData(
          label: '@${role.name}',
          color: accordRoleColor(role.color) ?? _mentionColor,
        );
      }
      if (members != null) {
        final member = members.values.firstWhereOrNull((m) {
          final u = m.user?.username;
          if (u != null && u.toLowerCase() == lower) return true;
          final d = m.user?.displayName;
          return d != null && d.toLowerCase() == lower;
        });
        if (member != null) {
          final name = accordMemberName(member, fallback: userHandle);
          return _ChipData(label: '@$name', color: _mentionColor);
        }
      }
      return null;
    }
    final channelName = match.group(3);
    if (channelName != null && channels != null) {
      final lower = channelName.toLowerCase();
      final channel = channels.firstWhereOrNull((c) {
        final name = c.name;
        return name != null &&
            name.toLowerCase() == lower &&
            c.type != 'category';
      });
      if (channel != null) {
        return _ChipData(label: '#${channel.name}', color: _mentionColor);
      }
    }
    return null;
  }

  static bool _isWordChar(String ch) {
    if (ch.isEmpty) return false;
    final c = ch.codeUnitAt(0);
    if (c >= 0x30 && c <= 0x39) return true;
    if (c >= 0x41 && c <= 0x5A) return true;
    if (c >= 0x61 && c <= 0x7A) return true;
    if (c == 0x5F) return true;
    return c > 0x7F;
  }

  static const _mentionColor = Color(0xFF5865F2);
  static const _broadcastColor = Color(0xFFFAA61A);
}

class _ChipData {
  const _ChipData({required this.label, required this.color});
  final String label;
  final Color color;
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
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
