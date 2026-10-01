/// Pure decision for whether an incoming message should raise a local
/// notification, kept out of the gateway handler so the policy can be
/// unit-tested.
///
/// Only messages that mention you (directly, by role, or via a non-suppressed
/// `@everyone`) notify, never your own messages, never the channel you're
/// currently looking at, and only while notifications are enabled.
class MessageNotificationGate {
  const MessageNotificationGate._();

  /// Whether a message should count as mentioning the current user across
  /// notifications, sounds, unread badges, and message-row highlighting.
  /// Direct and role mentions are never suppressed; the user preference only
  /// applies to broadcast mentions.
  ///
  /// Badge counts are decided when a gateway event is ingested, so changing
  /// [suppressEveryone] does not rewrite already-stored unread counts.
  static bool countsAsMention({
    required bool mentionsMe,
    required bool mentionEveryone,
    required bool suppressEveryone,
  }) => mentionsMe || (mentionEveryone && !suppressEveryone);

  /// Returns true when a notification should be shown.
  ///
  /// [notificationsEnabled] mirrors `AccordSettings.notificationsEnabled`;
  /// [suppressEveryone] mirrors `AccordSettings.suppressEveryone`.
  /// [isOwnMessage] is true when the message author is the current user;
  /// [isVisibleChannel] is true when the message lands in the channel currently
  /// on screen. [mentionsMe] folds direct + role mentions; [mentionEveryone] is
  /// the raw `@everyone`/`@here` flag (gated here by [suppressEveryone]).
  ///
  /// [channelLevel] overrides the default mention-only behaviour per channel:
  /// `'all'` notifies for every message, `'mentions'` is the default behaviour
  /// (kept for clarity), `'nothing'` suppresses unconditionally. `null` falls
  /// back to the default. Mirrors the reference client's per-channel level
  /// (`Config.get_channel_notification_level`).
  /// [spaceMuted] mirrors a per-space mute (`AccordSettings.isSpaceMuted`): when
  /// true the message's space is muted and no notification is shown, regardless
  /// of mentions.
  /// [isDirectMessage] is true for a DM / group-DM message (no parent space).
  /// A DM is addressed to you by definition, so it notifies without needing an
  /// `@mention`; an explicit per-channel `'mentions'` level still
  /// narrows it back to mention-only, and `'nothing'` still silences it.
  static bool shouldNotify({
    required bool notificationsEnabled,
    required bool suppressEveryone,
    required bool isOwnMessage,
    required bool isVisibleChannel,
    required bool mentionsMe,
    required bool mentionEveryone,
    bool spaceMuted = false,
    String? channelLevel,
    bool isDirectMessage = false,
  }) {
    if (!notificationsEnabled) return false;
    if (isOwnMessage) return false;
    if (isVisibleChannel) return false;
    if (spaceMuted) return false;
    // The user-set per-channel level overrides the mention default, but is
    // still gated by the higher-priority knobs above (global enable, self,
    // visible channel) so a single setting can't accidentally re-enable an
    // explicitly-disabled stream.
    if (channelLevel == 'nothing') return false;
    if (channelLevel == 'all') return true;
    if (isDirectMessage && channelLevel == null) return true;
    return countsAsMention(
      mentionsMe: mentionsMe,
      mentionEveryone: mentionEveryone,
      suppressEveryone: suppressEveryone,
    );
  }
}
