import 'package:bonfire/theme/app_theme.dart';

/// User-facing client preferences, persisted in the `accord-settings` Hive box.
/// Distinct from server/account state ([AccordSession]); these are local-only.
class AccordSettings {
  /// Default master-server directory URL (matches the reference client).
  static const String defaultMasterServerUrl = 'https://master.daccord.gg';

  /// Per-channel notification levels — `channel_id → 'all' | 'mentions' |
  /// 'nothing'`. Missing entries fall back to the global default ("mentions").
  /// Mirrors the reference client's `Config.set_channel_notification_level`.
  static const String channelNotifAll = 'all';
  static const String channelNotifMentions = 'mentions';
  static const String channelNotifNothing = 'nothing';

  const AccordSettings({
    this.themePreset = AppThemePreset.dark,
    this.accentColor,
    this.notificationsEnabled = true,
    this.suppressEveryone = false,
    this.soundsEnabled = true,
    this.sfxVolume = 1.0,
    this.recentEmoji = const [],
    this.masterServerUrl = defaultMasterServerUrl,
    this.channelNotifications = const <String, String>{},
    this.acceptedRuleSpaces = const <String>[],
    this.acknowledgedNsfwChannels = const <String>[],
    this.collapsedCategories = const <String, List<String>>{},
    this.drafts = const <String, String>{},
  });

  /// Selected colour theme.
  final AppThemePreset themePreset;

  /// Optional accent (primary) override as an ARGB int; null = preset default.
  final int? accentColor;

  /// Whether to show local notifications for mentions.
  final bool notificationsEnabled;

  /// When true, `@everyone` mentions never raise a notification.
  final bool suppressEveryone;

  /// Whether to play SFX (message sent/received, mentions).
  final bool soundsEnabled;

  /// SFX playback volume, 0.0–1.0.
  final double sfxVolume;

  /// Most-recently-used emoji tokens (unicode chars or `name:id` custom refs),
  /// most-recent first.
  final List<String> recentEmoji;

  /// Master-server directory URL used to browse public spaces (unauthenticated).
  final String masterServerUrl;

  /// Per-channel notification overrides keyed by channel ID. A missing entry
  /// means "use the global default" (mention-only).
  final Map<String, String> channelNotifications;

  /// Space IDs whose rules interstitial the user has accepted. Persisted so the
  /// dialog isn't reshown on every join/restart. Mirrors the reference client's
  /// `Config.set_rules_accepted` / `has_rules_accepted`.
  final List<String> acceptedRuleSpaces;

  /// Channel IDs whose age-restricted (NSFW) gate the user has confirmed.
  /// Mirrors the reference client's persisted `nsfw_ack`.
  final List<String> acknowledgedNsfwChannels;

  /// Collapsed channel categories per space — `space_id → [category_id, ...]`.
  /// Mirrors the reference client's `Config.set_category_collapsed`.
  final Map<String, List<String>> collapsedCategories;

  /// Unsent message drafts keyed by channel ID. Mirrors the reference client's
  /// `Config.set_draft_text` / `get_draft_text`.
  final Map<String, String> drafts;

  AccordSettings copyWith({
    AppThemePreset? themePreset,
    int? accentColor,
    bool clearAccentColor = false,
    bool? notificationsEnabled,
    bool? suppressEveryone,
    bool? soundsEnabled,
    double? sfxVolume,
    List<String>? recentEmoji,
    String? masterServerUrl,
    Map<String, String>? channelNotifications,
    List<String>? acceptedRuleSpaces,
    List<String>? acknowledgedNsfwChannels,
    Map<String, List<String>>? collapsedCategories,
    Map<String, String>? drafts,
  }) {
    return AccordSettings(
      themePreset: themePreset ?? this.themePreset,
      accentColor:
          clearAccentColor ? null : (accentColor ?? this.accentColor),
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      suppressEveryone: suppressEveryone ?? this.suppressEveryone,
      soundsEnabled: soundsEnabled ?? this.soundsEnabled,
      sfxVolume: sfxVolume ?? this.sfxVolume,
      recentEmoji: recentEmoji ?? this.recentEmoji,
      masterServerUrl: masterServerUrl ?? this.masterServerUrl,
      channelNotifications: channelNotifications ?? this.channelNotifications,
      acceptedRuleSpaces: acceptedRuleSpaces ?? this.acceptedRuleSpaces,
      acknowledgedNsfwChannels:
          acknowledgedNsfwChannels ?? this.acknowledgedNsfwChannels,
      collapsedCategories: collapsedCategories ?? this.collapsedCategories,
      drafts: drafts ?? this.drafts,
    );
  }

  /// Whether the rules interstitial for [spaceId] has been accepted.
  bool isRulesAccepted(String spaceId) => acceptedRuleSpaces.contains(spaceId);

  /// Whether the NSFW gate for [channelId] has been acknowledged.
  bool isNsfwAcknowledged(String channelId) =>
      acknowledgedNsfwChannels.contains(channelId);

  /// Whether [categoryId] is collapsed in [spaceId]'s channel list.
  bool isCategoryCollapsed(String spaceId, String categoryId) =>
      collapsedCategories[spaceId]?.contains(categoryId) ?? false;

  /// The saved draft for [channelId], or empty string when none.
  String draftFor(String channelId) => drafts[channelId] ?? '';

  /// Returns the level set for [channelId], or null when the user hasn't
  /// overridden it (callers fall back to the default mention-only behaviour).
  String? channelNotificationLevel(String channelId) =>
      channelNotifications[channelId];

  Map<String, dynamic> toJson() => {
        'themePreset': themePreset.name,
        'accentColor': accentColor,
        'notificationsEnabled': notificationsEnabled,
        'suppressEveryone': suppressEveryone,
        'soundsEnabled': soundsEnabled,
        'sfxVolume': sfxVolume,
        'recentEmoji': recentEmoji,
        'masterServerUrl': masterServerUrl,
        'channelNotifications': channelNotifications,
        'acceptedRuleSpaces': acceptedRuleSpaces,
        'acknowledgedNsfwChannels': acknowledgedNsfwChannels,
        'collapsedCategories': collapsedCategories,
        'drafts': drafts,
      };

  factory AccordSettings.fromJson(Map<dynamic, dynamic> json) {
    final master = (json['masterServerUrl'] as String?)?.trim();
    return AccordSettings(
      themePreset: AppThemePreset.fromName(json['themePreset'] as String?),
      accentColor: (json['accentColor'] as num?)?.toInt(),
      notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
      suppressEveryone: json['suppressEveryone'] as bool? ?? false,
      soundsEnabled: json['soundsEnabled'] as bool? ?? true,
      sfxVolume: (json['sfxVolume'] as num?)?.toDouble() ?? 1.0,
      recentEmoji: [
        for (final e in (json['recentEmoji'] as List? ?? const []))
          e.toString(),
      ],
      masterServerUrl:
          (master == null || master.isEmpty) ? defaultMasterServerUrl : master,
      channelNotifications: {
        for (final entry
            in (json['channelNotifications'] as Map? ?? const {}).entries)
          entry.key.toString(): entry.value.toString(),
      },
      acceptedRuleSpaces: [
        for (final e in (json['acceptedRuleSpaces'] as List? ?? const []))
          e.toString(),
      ],
      acknowledgedNsfwChannels: [
        for (final e in (json['acknowledgedNsfwChannels'] as List? ?? const []))
          e.toString(),
      ],
      collapsedCategories: {
        for (final entry
            in (json['collapsedCategories'] as Map? ?? const {}).entries)
          entry.key.toString(): [
            for (final c in (entry.value as List? ?? const [])) c.toString(),
          ],
      },
      drafts: {
        for (final entry in (json['drafts'] as Map? ?? const {}).entries)
          entry.key.toString(): entry.value.toString(),
      },
    );
  }
}
