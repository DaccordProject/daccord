/// Converts classic text emoticons (`:)`, `<3`, `xD`, …) into the matching
/// unicode emoji **on send**, the way Discord/Slack/Teams do.
///
/// Doing it on send (rather than on render) means the stored message content
/// holds the real glyph, so every other client — the Godot reference client,
/// bots reading history, federated peers — sees exactly what we see.
///
/// The transform is markdown-aware: code spans, fenced code blocks, URLs and
/// `:shortcode:` emoji references are left untouched (see [applyEmoticons]).
library;

import 'package:bonfire/features/messaging/utils/emoji_catalog.dart';

/// Emoticon → catalog entry name. The glyphs themselves live in
/// [kEmojiCatalog], so this table never carries a second copy of them.
///
/// Ordering here is presentational only; matching is longest-token-first (so
/// `:'(` beats `:(` and `</3` beats `<3`) — see [_orderedEmoticons].
const Map<String, String> kEmoticonNames = {
  ':)': 'slight_smile',
  ':-)': 'slight_smile',
  '(:': 'slight_smile',
  ':(': 'slight_frown',
  ':-(': 'slight_frown',
  ":'(": 'cry',
  ':D': 'smiley',
  ':-D': 'smiley',
  ';)': 'wink',
  ';-)': 'wink',
  ':P': 'stuck_out_tongue',
  ':p': 'stuck_out_tongue',
  ':-P': 'stuck_out_tongue',
  ':O': 'open_mouth',
  ':o': 'open_mouth',
  ':/': 'confused',
  ':-/': 'confused',
  ':|': 'neutral',
  '>:(': 'angry',
  'xD': 'laughing',
  'XD': 'laughing',
  '<3': 'heart',
  '</3': 'broken_heart',
  ':*': 'kissing_heart',
  'o/': 'wave',
  '\\o': 'wave',
};

/// Emoticon → glyph, resolved once from [kEmojiCatalog] via
/// [resolveEmojiGlyph].
final Map<String, String> kEmoticons = {
  for (final entry in kEmoticonNames.entries)
    entry.key: resolveEmojiGlyph(entry.value),
};

/// [kEmoticons] as (token, glyph) pairs sorted longest-token-first, so the
/// scanner always prefers the more specific emoticon at a given position.
final List<MapEntry<String, String>> _orderedEmoticons =
    kEmoticons.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));

/// Characters allowed immediately after an emoticon. Anything else (a letter,
/// digit, `/`, …) means we're mid-word or mid-URL and must not convert.
const String _trailingPunctuation = r'''.,!?;:'")]}''';

/// A protected `[start, end)` slice of the source that must be copied through
/// verbatim.
typedef _Range = ({int start, int end});

/// Fenced code block delimiters (``` / ~~~), optionally indented up to three
/// spaces, with an optional info string.
final RegExp _fenceLine = RegExp(r'^ {0,3}(`{3,}|~{3,})');

/// Absolute URLs (`https://…`, `daccord://…`) and bare `www.` links. Everything
/// up to the next whitespace belongs to the link.
final RegExp _urlPattern = RegExp(r'(?:[A-Za-z][A-Za-z0-9+.\-]*://|www\.)\S+');

/// Colon-wrapped emoji shortcodes (`:tada:`) and custom-emoji tags
/// (`<:party:123>`). Mirrors the `:([A-Za-z0-9_]+):` syntax the message
/// renderer and the reaction/picker code already parse.
final RegExp _shortcodePattern = RegExp(
  r'<a?:[A-Za-z0-9_]+:\d+>|:[A-Za-z0-9_]+:',
);

/// Replaces text emoticons in [content] with their emoji, leaving markdown
/// code, links and shortcodes alone. Pure — no I/O, no settings lookup — so
/// callers gate it on `AccordSettings.convertEmoticons` themselves.
///
/// Not converted:
/// * inline code spans (`` `:)` ``) and fenced code blocks;
/// * anything inside a URL (`https://example.com/foo:)bar`);
/// * mid-word runs — an emoticon needs the start of the string or whitespace
///   before it and whitespace, the end, or punctuation after it, so `a:)`,
///   `foo:Dbar`, `10:00`, `1:1` and `foo:/bar` all survive;
/// * `:shortcode:` / `<:name:id>` emoji references.
String applyEmoticons(String content) {
  if (content.isEmpty) return content;

  final protected = _protectedRanges(content);
  final buffer = StringBuffer();
  var i = 0;
  var next = 0;

  while (i < content.length) {
    while (next < protected.length && protected[next].end <= i) {
      next++;
    }
    if (next < protected.length && i >= protected[next].start) {
      buffer.write(content.substring(i, protected[next].end));
      i = protected[next].end;
      continue;
    }

    final match = _emoticonAt(content, i);
    if (match != null) {
      buffer.write(match.value);
      i += match.key.length;
      continue;
    }

    buffer.write(content[i]);
    i++;
  }

  return buffer.toString();
}

/// The emoticon starting at [index], or null when there is none (or when the
/// surrounding characters aren't word boundaries).
MapEntry<String, String>? _emoticonAt(String content, int index) {
  // Boundary before: start of the message or whitespace. This is what keeps
  // `a:)`, `foo:/bar`, `10:00` and URL tails from converting.
  if (index > 0 && !_isWhitespace(content.codeUnitAt(index - 1))) return null;

  for (final emoticon in _orderedEmoticons) {
    final token = emoticon.key;
    if (!content.startsWith(token, index)) continue;
    final after = index + token.length;
    if (after < content.length) {
      final code = content.codeUnitAt(after);
      if (!_isWhitespace(code) &&
          !_trailingPunctuation.contains(content[after])) {
        continue;
      }
    }
    return emoticon;
  }
  return null;
}

bool _isWhitespace(int code) =>
    code == 0x20 || code == 0x09 || code == 0x0A || code == 0x0D;

/// The sorted, merged slices of [content] the scanner must skip: fenced code
/// blocks, inline code spans, URLs and emoji shortcodes.
List<_Range> _protectedRanges(String content) {
  final ranges = <_Range>[
    ..._fencedRanges(content),
    ..._codeSpanRanges(content),
    for (final m in _urlPattern.allMatches(content))
      (start: m.start, end: m.end),
    for (final m in _shortcodePattern.allMatches(content))
      (start: m.start, end: m.end),
  ];
  if (ranges.isEmpty) return const [];

  ranges.sort((a, b) => a.start.compareTo(b.start));
  final merged = <_Range>[ranges.first];
  for (final range in ranges.skip(1)) {
    final last = merged.last;
    if (range.start <= last.end) {
      if (range.end > last.end) {
        merged[merged.length - 1] = (start: last.start, end: range.end);
      }
    } else {
      merged.add(range);
    }
  }
  return merged;
}

/// Ranges covered by ``` / ~~~ fenced code blocks, opening fence line through
/// closing fence line. An unclosed fence protects the rest of the message,
/// matching how the markdown renderer treats it.
List<_Range> _fencedRanges(String content) {
  final ranges = <_Range>[];
  var offset = 0;
  String? openChar;
  var openLength = 0;
  var openStart = 0;

  for (final line in content.split('\n')) {
    final match = _fenceLine.firstMatch(line);
    if (openChar == null) {
      if (match != null) {
        final marker = match.group(1)!;
        openChar = marker[0];
        openLength = marker.length;
        openStart = offset;
      }
    } else if (match != null) {
      final marker = match.group(1)!;
      // A closing fence is the same character, at least as long, and carries
      // no info string.
      if (marker[0] == openChar &&
          marker.length >= openLength &&
          line.substring(match.end).trim().isEmpty) {
        ranges.add((start: openStart, end: offset + line.length));
        openChar = null;
      }
    }
    offset += line.length + 1;
  }

  if (openChar != null) {
    ranges.add((start: openStart, end: content.length));
  }
  return ranges;
}

/// Ranges covered by inline code spans, honouring CommonMark's rule that a run
/// of N backticks closes on the next run of exactly N backticks.
List<_Range> _codeSpanRanges(String content) {
  final ranges = <_Range>[];
  var i = 0;
  while (i < content.length) {
    if (content[i] != '`') {
      i++;
      continue;
    }
    final open = _backtickRun(content, i);
    var j = i + open;
    var closed = false;
    while (j < content.length) {
      if (content[j] != '`') {
        j++;
        continue;
      }
      final close = _backtickRun(content, j);
      if (close == open) {
        ranges.add((start: i, end: j + close));
        i = j + close;
        closed = true;
        break;
      }
      j += close;
    }
    if (!closed) i += open;
  }
  return ranges;
}

int _backtickRun(String content, int index) {
  var n = 0;
  while (index + n < content.length && content[index + n] == '`') {
    n++;
  }
  return n;
}
