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

  /// Sets the camera capture resolution index (0 = 480p, 1 = 720p, 2 = 1080p).
  void setVideoResolution(int index) => _update(state.copyWith(
        videoResolution:
            index.clamp(0, AccordSettings.videoResolutionLabels.length - 1)));

  /// Sets the camera capture frame rate; ignored when not one of
  /// [AccordSettings.videoFpsOptions].
  void setVideoFps(int fps) {
    if (!AccordSettings.videoFpsOptions.contains(fps)) return;
    _update(state.copyWith(videoFps: fps));
  }

  /// Sets the microphone device ID (empty = system default).
  void setAudioInputDevice(String deviceId) =>
      _update(state.copyWith(audioInputDeviceId: deviceId));

  /// Sets the speaker/output device ID (empty = system default).
  void setAudioOutputDevice(String deviceId) =>
      _update(state.copyWith(audioOutputDeviceId: deviceId));

  /// Sets the camera device ID (empty = system default).
  void setVideoInputDevice(String deviceId) =>
      _update(state.copyWith(videoInputDeviceId: deviceId));

  /// Sets the microphone input volume percentage, clamped to 0–200.
  void setInputVolume(int volume) =>
      _update(state.copyWith(inputVolume: volume.clamp(0, 200)));

  /// Sets the remote-audio output volume percentage, clamped to 0–200.
  void setOutputVolume(int volume) =>
      _update(state.copyWith(outputVolume: volume.clamp(0, 200)));

  /// Sets the voice-activity sensitivity, clamped to 0–100.
  void setInputSensitivity(int sensitivity) =>
      _update(state.copyWith(inputSensitivity: sensitivity.clamp(0, 100)));

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

  /// Marks [spaceId]'s rules interstitial as accepted so it isn't reshown.
  void acceptRules(String spaceId) {
    if (state.acceptedRuleSpaces.contains(spaceId)) return;
    _update(state.copyWith(
        acceptedRuleSpaces: [...state.acceptedRuleSpaces, spaceId]));
  }

  /// Marks [channelId]'s NSFW gate as acknowledged.
  void acknowledgeNsfw(String channelId) {
    if (state.acknowledgedNsfwChannels.contains(channelId)) return;
    _update(state.copyWith(
        acknowledgedNsfwChannels: [...state.acknowledgedNsfwChannels, channelId]));
  }

  /// Sets whether [categoryId] is collapsed in [spaceId]'s channel list.
  void setCategoryCollapsed(String spaceId, String categoryId, bool collapsed) {
    final current = state.collapsedCategories[spaceId] ?? const <String>[];
    final isCollapsed = current.contains(categoryId);
    if (collapsed == isCollapsed) return;
    final nextList = collapsed
        ? [...current, categoryId]
        : [for (final c in current) if (c != categoryId) c];
    final next = Map<String, List<String>>.from(state.collapsedCategories);
    if (nextList.isEmpty) {
      next.remove(spaceId);
    } else {
      next[spaceId] = nextList;
    }
    _update(state.copyWith(collapsedCategories: next));
  }

  /// Saves (or clears, when [text] is blank) the unsent draft for [channelId].
  void setDraft(String channelId, String text) {
    final trimmed = text;
    final current = state.drafts[channelId] ?? '';
    if (current == trimmed) return;
    final next = Map<String, String>.from(state.drafts);
    if (trimmed.isEmpty) {
      next.remove(channelId);
    } else {
      next[channelId] = trimmed;
    }
    _update(state.copyWith(drafts: next));
  }
}
