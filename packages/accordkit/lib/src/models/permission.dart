/// Permission name constants and helpers. Permissions are represented as
/// string identifiers throughout the API.
class AccordPermission {
  static const String createInvites = 'create_invites';
  static const String kickMembers = 'kick_members';
  static const String banMembers = 'ban_members';
  static const String administrator = 'administrator';
  static const String manageChannels = 'manage_channels';
  static const String manageSpace = 'manage_space';
  static const String addReactions = 'add_reactions';
  static const String viewAuditLog = 'view_audit_log';
  static const String prioritySpeaker = 'priority_speaker';
  static const String stream = 'stream';
  static const String viewChannel = 'view_channel';
  static const String sendMessages = 'send_messages';
  static const String sendTts = 'send_tts';
  static const String manageMessages = 'manage_messages';
  static const String embedLinks = 'embed_links';
  static const String attachFiles = 'attach_files';
  static const String readHistory = 'read_history';
  static const String mentionEveryone = 'mention_everyone';
  static const String useExternalEmojis = 'use_external_emojis';
  static const String connect = 'connect';
  static const String speak = 'speak';
  static const String muteMembers = 'mute_members';
  static const String deafenMembers = 'deafen_members';
  static const String moveMembers = 'move_members';
  static const String useVad = 'use_vad';
  static const String changeNickname = 'change_nickname';
  static const String manageNicknames = 'manage_nicknames';
  static const String manageRoles = 'manage_roles';
  static const String manageWebhooks = 'manage_webhooks';
  static const String manageEmojis = 'manage_emojis';
  static const String manageSoundboard = 'manage_soundboard';
  static const String useSoundboard = 'use_soundboard';
  static const String useCommands = 'use_commands';
  static const String manageEvents = 'manage_events';
  static const String manageThreads = 'manage_threads';
  static const String createThreads = 'create_threads';
  static const String useExternalStickers = 'use_external_stickers';
  static const String sendInThreads = 'send_in_threads';
  static const String moderateMembers = 'moderate_members';
  static const String manageAutomod = 'manage_automod';

  /// Every known permission identifier.
  static List<String> all() => const [
        createInvites,
        kickMembers,
        banMembers,
        administrator,
        manageChannels,
        manageSpace,
        addReactions,
        viewAuditLog,
        prioritySpeaker,
        stream,
        viewChannel,
        sendMessages,
        sendTts,
        manageMessages,
        embedLinks,
        attachFiles,
        readHistory,
        mentionEveryone,
        useExternalEmojis,
        connect,
        speak,
        muteMembers,
        deafenMembers,
        moveMembers,
        useVad,
        changeNickname,
        manageNicknames,
        manageRoles,
        manageWebhooks,
        manageEmojis,
        manageSoundboard,
        useSoundboard,
        useCommands,
        manageEvents,
        manageThreads,
        createThreads,
        useExternalStickers,
        sendInThreads,
        moderateMembers,
        manageAutomod,
      ];

  /// Whether [permissions] grants [perm]. [administrator] implies all.
  static bool has(List<String> permissions, String perm) {
    return permissions.contains(perm) || permissions.contains(administrator);
  }

  /// A human-readable description for a permission, or empty if unknown.
  static String description(String perm) {
    switch (perm) {
      case createInvites:
        return 'Allows creating invite links to the space';
      case kickMembers:
        return 'Allows kicking members from the space';
      case banMembers:
        return 'Allows banning members from the space';
      case administrator:
        return 'Grants all permissions and bypasses all checks';
      case manageChannels:
        return 'Allows creating, editing, and deleting channels';
      case manageSpace:
        return 'Allows editing space name, icon, and settings';
      case addReactions:
        return 'Allows adding reactions to messages';
      case viewAuditLog:
        return 'Allows viewing the audit log';
      case prioritySpeaker:
        return 'Allows being heard over other users in voice';
      case stream:
        return 'Allows screen sharing in voice channels';
      case viewChannel:
        return 'Allows viewing a channel';
      case sendMessages:
        return 'Allows sending messages in text channels';
      case sendTts:
        return 'Allows sending text-to-speech messages';
      case manageMessages:
        return 'Allows deleting and pinning messages from other users';
      case embedLinks:
        return 'Allows link previews to be shown for sent messages';
      case attachFiles:
        return 'Allows uploading files and images';
      case readHistory:
        return 'Allows reading message history';
      case mentionEveryone:
        return 'Allows using @everyone and @here mentions';
      case useExternalEmojis:
        return 'Allows using emojis from other spaces';
      case connect:
        return 'Allows joining voice channels';
      case speak:
        return 'Allows speaking in voice channels';
      case muteMembers:
        return 'Allows muting other members in voice channels';
      case deafenMembers:
        return 'Allows deafening other members in voice channels';
      case moveMembers:
        return 'Allows moving members between voice channels';
      case useVad:
        return 'Allows using voice activity detection instead of push-to-talk';
      case changeNickname:
        return 'Allows changing own nickname';
      case manageNicknames:
        return 'Allows changing nicknames of other members';
      case manageRoles:
        return 'Allows creating and editing roles below their highest role';
      case manageWebhooks:
        return 'Allows creating, editing, and deleting webhooks';
      case manageEmojis:
        return 'Allows managing custom emojis';
      case manageSoundboard:
        return 'Allows managing soundboard sounds';
      case useSoundboard:
        return 'Allows playing soundboard sounds';
      case useCommands:
        return 'Allows using bot and slash commands';
      case manageEvents:
        return 'Allows creating, editing, and deleting events';
      case manageThreads:
        return 'Allows managing threads and forum posts';
      case createThreads:
        return 'Allows creating threads and forum posts';
      case useExternalStickers:
        return 'Allows using stickers from other spaces';
      case sendInThreads:
        return 'Allows sending messages in threads';
      case moderateMembers:
        return 'Allows timing out and moderating members';
      case manageAutomod:
        return 'Allows configuring auto-moderation rules';
    }
    return '';
  }
}
