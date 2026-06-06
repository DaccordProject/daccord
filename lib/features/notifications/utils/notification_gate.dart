/// Pure decision for whether an incoming message should raise a local
/// notification. The notification analogue of [SoundManager.soundForMessage]:
/// extracted from the gateway handler so the gating policy — which decides what
/// users actually get pinged for — can be unit-tested without a live gateway.
///
/// Mirrors the rule the reference client applies in its message handler: only
/// messages that mention you (directly, by role, or via a non-suppressed
/// `@everyone`) notify, never your own messages, never the channel you're
/// currently looking at, and only while notifications are enabled.
class MessageNotificationGate {
  const MessageNotificationGate._();

  /// Returns true when a notification should be shown.
  ///
  /// [notificationsEnabled] mirrors `AccordSettings.notificationsEnabled`;
  /// [suppressEveryone] mirrors `AccordSettings.suppressEveryone`.
  /// [isOwnMessage] is true when the message author is the current user;
  /// [isVisibleChannel] is true when the message lands in the channel currently
  /// on screen. [mentionsMe] folds direct + role mentions; [mentionEveryone] is
  /// the raw `@everyone`/`@here` flag (gated here by [suppressEveryone]).
  static bool shouldNotify({
    required bool notificationsEnabled,
    required bool suppressEveryone,
    required bool isOwnMessage,
    required bool isVisibleChannel,
    required bool mentionsMe,
    required bool mentionEveryone,
  }) {
    if (!notificationsEnabled) return false;
    if (isOwnMessage) return false;
    if (isVisibleChannel) return false;
    final everyone = mentionEveryone && !suppressEveryone;
    return mentionsMe || everyone;
  }
}
