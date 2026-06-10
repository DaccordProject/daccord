import '../utils/json_utils.dart';

/// An aggregated reaction on a message.
class AccordReaction {
  /// `{ "id": String?, "name": String }`.
  Map<String, dynamic> emoji;
  int count;
  bool includesMe;

  AccordReaction({
    Map<String, dynamic>? emoji,
    this.count = 0,
    this.includesMe = false,
  }) : emoji = emoji ?? {};

  factory AccordReaction.fromJson(Map<String, dynamic> d) {
    final emoji = <String, dynamic>{};
    final rawEmoji = d['emoji'];
    if (rawEmoji is Map) {
      final m = rawEmoji.cast<String, dynamic>();
      emoji['id'] = asStringOrNull(m['id']);
      emoji['name'] = asString(m['name']);
    } else if (rawEmoji is String) {
      // Custom emoji travel as the bare token `name:id` (id a numeric
      // snowflake); unicode emoji arrive as a glyph or shortcode. Split the
      // custom form so the id survives — otherwise the whole `name:id` string
      // lands in `name` with a null id and renders as literal text.
      final i = rawEmoji.lastIndexOf(':');
      if (i > 0 &&
          i < rawEmoji.length - 1 &&
          rawEmoji
              .substring(i + 1)
              .codeUnits
              .every((c) => c >= 0x30 && c <= 0x39)) {
        emoji['id'] = rawEmoji.substring(i + 1);
        emoji['name'] = rawEmoji.substring(0, i);
      } else {
        emoji['id'] = null;
        emoji['name'] = rawEmoji;
      }
    }
    return AccordReaction(
      emoji: emoji,
      count: asInt(d['count']),
      includesMe: asBool(d['me'] ?? d['includes_me']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'emoji': emoji,
      'count': count,
      'includes_me': includesMe,
    };
  }
}
