/// Gateway intent identifiers and convenience groupings. Intents control which
/// event categories the gateway streams to a connection.
class GatewayIntents {
  static const String spaces = 'spaces';
  static const String moderation = 'moderation';
  static const String emojis = 'emojis';
  static const String voiceStates = 'voice_states';
  static const String messages = 'messages';
  static const String messageReactions = 'message_reactions';
  static const String messageTyping = 'message_typing';
  static const String directMessages = 'direct_messages';
  static const String dmReactions = 'dm_reactions';
  static const String dmTyping = 'dm_typing';
  static const String scheduledEvents = 'scheduled_events';
  static const String plugins = 'plugins';
  static const String relationships = 'relationships';
  static const String soundboard = 'soundboard';

  // Privileged intents.
  static const String members = 'members';
  static const String presences = 'presences';
  static const String messageContent = 'message_content';

  static List<String> unprivileged() => const [
        spaces,
        moderation,
        emojis,
        voiceStates,
        messages,
        messageReactions,
        messageTyping,
        directMessages,
        dmReactions,
        dmTyping,
        scheduledEvents,
        plugins,
        relationships,
        soundboard,
      ];

  static List<String> privileged() =>
      const [members, presences, messageContent];

  static List<String> all() => [...unprivileged(), ...privileged()];

  static List<String> defaults() => const [spaces, messages, messageContent];

  /// Reduced intent set for anonymous guest connections — space structure,
  /// messages, and member count updates only.
  static List<String> guest() =>
      const [spaces, messages, messageContent, members];
}
