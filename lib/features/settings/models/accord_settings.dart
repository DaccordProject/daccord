import 'package:bonfire/theme/app_theme.dart';

/// User-facing client preferences, persisted in the `accord-settings` Hive box.
/// Distinct from server/account state ([AccordSession]); these are local-only.
class AccordSettings {
  /// Default master-server directory URL (matches the reference client).
  static const String defaultMasterServerUrl = 'https://master.daccord.gg';

  const AccordSettings({
    this.themePreset = AppThemePreset.dark,
    this.accentColor,
    this.notificationsEnabled = true,
    this.suppressEveryone = false,
    this.soundsEnabled = true,
    this.sfxVolume = 1.0,
    this.recentEmoji = const [],
    this.masterServerUrl = defaultMasterServerUrl,
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
    );
  }

  Map<String, dynamic> toJson() => {
        'themePreset': themePreset.name,
        'accentColor': accentColor,
        'notificationsEnabled': notificationsEnabled,
        'suppressEveryone': suppressEveryone,
        'soundsEnabled': soundsEnabled,
        'sfxVolume': sfxVolume,
        'recentEmoji': recentEmoji,
        'masterServerUrl': masterServerUrl,
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
    );
  }
}
