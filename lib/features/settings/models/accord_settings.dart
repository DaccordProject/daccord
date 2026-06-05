import 'package:bonfire/theme/app_theme.dart';

/// User-facing client preferences, persisted in the `accord-settings` Hive box.
/// Distinct from server/account state ([AccordSession]); these are local-only.
class AccordSettings {
  const AccordSettings({
    this.themePreset = AppThemePreset.dark,
    this.accentColor,
    this.notificationsEnabled = true,
    this.suppressEveryone = false,
    this.recentEmoji = const [],
  });

  /// Selected colour theme.
  final AppThemePreset themePreset;

  /// Optional accent (primary) override as an ARGB int; null = preset default.
  final int? accentColor;

  /// Whether to show local notifications for mentions.
  final bool notificationsEnabled;

  /// When true, `@everyone` mentions never raise a notification.
  final bool suppressEveryone;

  /// Most-recently-used emoji tokens (unicode chars or `name:id` custom refs),
  /// most-recent first.
  final List<String> recentEmoji;

  AccordSettings copyWith({
    AppThemePreset? themePreset,
    int? accentColor,
    bool clearAccentColor = false,
    bool? notificationsEnabled,
    bool? suppressEveryone,
    List<String>? recentEmoji,
  }) {
    return AccordSettings(
      themePreset: themePreset ?? this.themePreset,
      accentColor:
          clearAccentColor ? null : (accentColor ?? this.accentColor),
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      suppressEveryone: suppressEveryone ?? this.suppressEveryone,
      recentEmoji: recentEmoji ?? this.recentEmoji,
    );
  }

  Map<String, dynamic> toJson() => {
        'themePreset': themePreset.name,
        'accentColor': accentColor,
        'notificationsEnabled': notificationsEnabled,
        'suppressEveryone': suppressEveryone,
        'recentEmoji': recentEmoji,
      };

  factory AccordSettings.fromJson(Map<dynamic, dynamic> json) {
    return AccordSettings(
      themePreset: AppThemePreset.fromName(json['themePreset'] as String?),
      accentColor: (json['accentColor'] as num?)?.toInt(),
      notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
      suppressEveryone: json['suppressEveryone'] as bool? ?? false,
      recentEmoji: [
        for (final e in (json['recentEmoji'] as List? ?? const []))
          e.toString(),
      ],
    );
  }
}
