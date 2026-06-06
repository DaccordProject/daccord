import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:hive_ce/hive.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'settings.g.dart';

/// Local client preferences (theme, notifications, recent emoji), persisted to
/// the `accord-settings` Hive box (opened in `setupHive`). Watched by `main`
/// to build the active [ThemeData] and by the notification + emoji layers.
@Riverpod(keepAlive: true)
class SettingsController extends _$SettingsController {
  static const _boxName = 'accord-settings';
  static const _key = 'settings';
  static const _maxRecentEmoji = 24;

  @override
  AccordSettings build() {
    final box = Hive.box(_boxName);
    final raw = box.get(_key);
    if (raw is Map) return AccordSettings.fromJson(raw);
    return const AccordSettings();
  }

  void _update(AccordSettings next) {
    state = next;
    Hive.box(_boxName).put(_key, next.toJson());
  }

  void setThemePreset(AppThemePreset preset) =>
      _update(state.copyWith(themePreset: preset));

  /// Sets the accent override, or clears it (revert to the preset default) when
  /// [argb] is null.
  void setAccentColor(int? argb) => _update(
        argb == null
            ? state.copyWith(clearAccentColor: true)
            : state.copyWith(accentColor: argb),
      );

  void setNotificationsEnabled(bool enabled) =>
      _update(state.copyWith(notificationsEnabled: enabled));

  void setSuppressEveryone(bool suppress) =>
      _update(state.copyWith(suppressEveryone: suppress));

  void setSoundsEnabled(bool enabled) =>
      _update(state.copyWith(soundsEnabled: enabled));

  void setSfxVolume(double volume) =>
      _update(state.copyWith(sfxVolume: volume.clamp(0.0, 1.0).toDouble()));

  /// Sets the master-server directory URL, falling back to the default when
  /// cleared/blank.
  void setMasterServerUrl(String url) {
    final trimmed = url.trim();
    _update(state.copyWith(
        masterServerUrl: trimmed.isEmpty
            ? AccordSettings.defaultMasterServerUrl
            : trimmed));
  }

  /// Sets the per-channel notification level for [channelId] — `'all'`,
  /// `'mentions'`, or `'nothing'`. Pass `null` to clear the override and fall
  /// back to the global default (mention-only). Mirrors the reference
  /// `Config.set_channel_notification_level`.
  void setChannelNotificationLevel(String channelId, String? level) {
    final next = Map<String, String>.from(state.channelNotifications);
    if (level == null || level.isEmpty) {
      if (!next.containsKey(channelId)) return;
      next.remove(channelId);
    } else {
      if (next[channelId] == level) return;
      next[channelId] = level;
    }
    _update(state.copyWith(channelNotifications: next));
  }

  /// Records [token] (a unicode char or `name:id` custom ref) as most-recently
  /// used, de-duplicating and capping the list.
  void addRecentEmoji(String token) {
    if (token.isEmpty) return;
    final next = [token, ...state.recentEmoji.where((e) => e != token)];
    if (next.length > _maxRecentEmoji) next.removeRange(_maxRecentEmoji, next.length);
    _update(state.copyWith(recentEmoji: next));
  }
}
