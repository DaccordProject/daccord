import 'dart:math';

import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/spaces/models/space_folder.dart';
import 'package:bonfire/features/voice/utils/afk_logic.dart';
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

  /// Android only: keep a foreground service (and so the gateway connection)
  /// alive while the app is backgrounded.
  void setBackgroundConnection(bool enabled) =>
      _update(state.copyWith(backgroundConnection: enabled));

  void setSoundsEnabled(bool enabled) =>
      _update(state.copyWith(soundsEnabled: enabled));

  void setSfxVolume(double volume) =>
      _update(state.copyWith(sfxVolume: volume.clamp(0.0, 1.0).toDouble()));

  /// Sets the camera capture resolution index (0 = 480p, 1 = 720p, 2 = 1080p).
  void setVideoResolution(int index) => _update(
    state.copyWith(
      videoResolution: index.clamp(
        0,
        AccordSettings.videoResolutionLabels.length - 1,
      ),
    ),
  );

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

  /// Sets the voice AFK idle timeout in minutes (0 = off). Clamped to
  /// non-negative; the UI only offers [afkTimeoutOptionsMinutes].
  void setVoiceAfkTimeoutMinutes(int minutes) =>
      _update(state.copyWith(voiceAfkTimeoutMinutes: max(0, minutes)));

  /// Whether going AFK should move us into the space's AFK channel.
  void setVoiceAfkAutoMove(bool enabled) =>
      _update(state.copyWith(voiceAfkAutoMove: enabled));

  /// Sets the master-server directory URL, falling back to the default when
  /// cleared/blank.
  void setMasterServerUrl(String url) {
    final trimmed = url.trim();
    _update(
      state.copyWith(
        masterServerUrl: trimmed.isEmpty
            ? AccordSettings.defaultMasterServerUrl
            : trimmed,
      ),
    );
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

  /// Sets compact (vs cozy) message density.
  void setCompactMode(bool enabled) =>
      _update(state.copyWith(compactMode: enabled));

  /// Enables/disables converting text emoticons (`:)`, `<3`) to emoji on send.
  void setConvertEmoticons(bool enabled) =>
      _update(state.copyWith(convertEmoticons: enabled));

  /// Enables/disables reduced motion (fewer UI animations).
  void setReducedMotion(bool enabled) =>
      _update(state.copyWith(reducedMotion: enabled));

  /// Sets the app-wide UI text scale, clamped to the supported range.
  void setUiScale(double scale) => _update(
    state.copyWith(
      uiScale: scale.clamp(
        AccordSettings.minUiScale,
        AccordSettings.maxUiScale,
      ),
    ),
  );

  /// Sets the desktop channel-list column width, clamped to the supported range.
  void setChannelListWidth(double width) => _update(
    state.copyWith(
      channelListWidth: width.clamp(
        AccordSettings.minChannelListWidth,
        AccordSettings.maxChannelListWidth,
      ),
    ),
  );

  // ── Rail ordering & folders ───────────────────────────────────────────────

  /// Persists the manual rail space ordering (a flat list of space ids).
  void setSpaceOrder(List<String> order) =>
      _update(state.copyWith(spaceOrder: order));

  /// Creates a folder containing [spaceIds] and returns its id.
  String createFolder({String name = '', List<String> spaceIds = const []}) {
    final id = 'folder-${_generateToken().substring(0, 12)}';
    // A space lives in at most one folder — strip these ids from any others.
    final cleaned = [
      for (final f in state.spaceFolders)
        f.copyWith(
          spaceIds: [
            for (final s in f.spaceIds)
              if (!spaceIds.contains(s)) s,
          ],
        ),
      SpaceFolder(id: id, name: name, spaceIds: spaceIds),
    ];
    _update(state.copyWith(spaceFolders: cleaned));
    return id;
  }

  void renameFolder(String id, String name) =>
      _mutateFolder(id, (f) => f.copyWith(name: name.trim()));

  void setFolderColor(String id, int? color) => _mutateFolder(
    id,
    (f) =>
        color == null ? f.copyWith(clearColor: true) : f.copyWith(color: color),
  );

  void setFolderCollapsed(String id, bool collapsed) =>
      _mutateFolder(id, (f) => f.copyWith(collapsed: collapsed));

  /// Removes [id], dissolving it (its spaces become ungrouped).
  void deleteFolder(String id) => _update(
    state.copyWith(
      spaceFolders: [
        for (final f in state.spaceFolders)
          if (f.id != id) f,
      ],
    ),
  );

  /// Moves [spaceId] into [folderId], or out of all folders when [folderId] is
  /// null. Within the target folder it is inserted before [before] (when that
  /// id is present) or appended otherwise — so this also reorders a space within
  /// a folder. Empty folders left behind are pruned.
  void moveSpaceToFolder(String spaceId, String? folderId, {String? before}) {
    final next = <SpaceFolder>[];
    for (final f in state.spaceFolders) {
      var ids = [
        for (final s in f.spaceIds)
          if (s != spaceId) s,
      ];
      if (f.id == folderId) {
        final at = before == null ? -1 : ids.indexOf(before);
        if (at < 0) {
          ids = [...ids, spaceId];
        } else {
          ids = [...ids.sublist(0, at), spaceId, ...ids.sublist(at)];
        }
      }
      final updated = f.copyWith(spaceIds: ids);
      // Drop folders emptied by this move (but keep the target).
      if (updated.spaceIds.isNotEmpty || updated.id == folderId) {
        next.add(updated);
      }
    }
    _update(state.copyWith(spaceFolders: next));
  }

  /// Mutes or unmutes [spaceId]'s notifications (per-space suppression). No-op
  /// when already in the requested state.
  void setSpaceMuted(String spaceId, bool muted) {
    final isMuted = state.mutedSpaces.contains(spaceId);
    if (muted == isMuted) return;
    _update(
      state.copyWith(
        mutedSpaces: muted
            ? [...state.mutedSpaces, spaceId]
            : [
                for (final s in state.mutedSpaces)
                  if (s != spaceId) s,
              ],
      ),
    );
  }

  /// Toggles the muted state of [spaceId].
  void toggleSpaceMuted(String spaceId) =>
      setSpaceMuted(spaceId, !state.mutedSpaces.contains(spaceId));

  /// Hides [spaceId] from the rail without leaving it, or restores it. No-op
  /// when already in the requested state.
  void setSpaceHidden(String spaceId, bool hidden) {
    final isHidden = state.hiddenSpaces.contains(spaceId);
    if (hidden == isHidden) return;
    _update(
      state.copyWith(
        hiddenSpaces: hidden
            ? [...state.hiddenSpaces, spaceId]
            : [
                for (final s in state.hiddenSpaces)
                  if (s != spaceId) s,
              ],
      ),
    );
  }

  void _mutateFolder(String id, SpaceFolder Function(SpaceFolder) fn) =>
      _update(
        state.copyWith(
          spaceFolders: [
            for (final f in state.spaceFolders)
              if (f.id == id) fn(f) else f,
          ],
        ),
      );

  /// Records [token] (a unicode char or `name:id` custom ref) as most-recently
  /// used, de-duplicating and capping the list.
  void addRecentEmoji(String token) {
    if (token.isEmpty) return;
    final next = [token, ...state.recentEmoji.where((e) => e != token)];
    if (next.length > _maxRecentEmoji)
      next.removeRange(_maxRecentEmoji, next.length);
    _update(state.copyWith(recentEmoji: next));
  }

  /// Marks [spaceId]'s rules interstitial as accepted so it isn't reshown.
  void acceptRules(String spaceId) {
    if (state.acceptedRuleSpaces.contains(spaceId)) return;
    _update(
      state.copyWith(
        acceptedRuleSpaces: [...state.acceptedRuleSpaces, spaceId],
      ),
    );
  }

  /// Marks [channelId]'s NSFW gate as acknowledged.
  void acknowledgeNsfw(String channelId) {
    if (state.acknowledgedNsfwChannels.contains(channelId)) return;
    _update(
      state.copyWith(
        acknowledgedNsfwChannels: [
          ...state.acknowledgedNsfwChannels,
          channelId,
        ],
      ),
    );
  }

  /// Sets whether [categoryId] is collapsed in [spaceId]'s channel list.
  void setCategoryCollapsed(String spaceId, String categoryId, bool collapsed) {
    final current = state.collapsedCategories[spaceId] ?? const <String>[];
    final isCollapsed = current.contains(categoryId);
    if (collapsed == isCollapsed) return;
    final nextList = collapsed
        ? [...current, categoryId]
        : [
            for (final c in current)
              if (c != categoryId) c,
          ];
    final next = Map<String, List<String>>.from(state.collapsedCategories);
    if (nextList.isEmpty) {
      next.remove(spaceId);
    } else {
      next[spaceId] = nextList;
    }
    _update(state.copyWith(collapsedCategories: next));
  }

  /// Enables/disables Developer Mode. Turning it off also disables the MCP
  /// server (mirrors the reference client's two-step opt-in).
  void setDeveloperMode(bool enabled) => _update(
    enabled
        ? state.copyWith(developerMode: true)
        : state.copyWith(developerMode: false, mcpEnabled: false),
  );

  /// Enables/disables the local Client MCP server. Generates a token on first
  /// enable if one isn't set yet.
  void setMcpEnabled(bool enabled) {
    if (enabled && state.mcpToken.isEmpty) {
      _update(state.copyWith(mcpEnabled: true, mcpToken: _generateToken()));
    } else {
      _update(state.copyWith(mcpEnabled: enabled));
    }
  }

  /// Sets the MCP server port, clamped to the valid TCP range.
  void setMcpPort(int port) =>
      _update(state.copyWith(mcpPort: port.clamp(1, 65535)));

  /// Regenerates the MCP bearer token.
  void regenerateMcpToken() =>
      _update(state.copyWith(mcpToken: _generateToken()));

  /// Sets whether [group] is exposed by the MCP server. Ignores unknown groups.
  void setMcpGroupAllowed(String group, bool allowed) {
    if (!AccordSettings.mcpToolGroups.contains(group)) return;
    final current = state.mcpAllowedGroups;
    final isAllowed = current.contains(group);
    if (allowed == isAllowed) return;
    final next = allowed
        ? [
            for (final g in AccordSettings.mcpToolGroups)
              if (current.contains(g) || g == group) g,
          ]
        : [
            for (final g in current)
              if (g != group) g,
          ];
    _update(state.copyWith(mcpAllowedGroups: next));
  }

  /// 32-byte random hex token, matching the reference client's
  /// `Crypto.generate_random_bytes(32)` hex encoding.
  String _generateToken() {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Enables/disables the startup update check.
  void setAutoUpdateCheck(bool enabled) =>
      _update(state.copyWith(autoUpdateCheck: enabled));

  /// Enables/disables anonymous error reporting (GlitchTip). Answering counts
  /// as having seen the consent prompt, so it is never reshown. Mirrors the
  /// reference's `Config.set_error_reporting_enabled` + consent stamping.
  void setErrorReportingEnabled(bool enabled) => _update(
    state.copyWith(
      errorReportingEnabled: enabled,
      errorReportingConsentShown: true,
    ),
  );

  /// Marks the first-launch error-reporting consent dialog as answered
  /// without changing the toggle. Mirrors the reference's
  /// `Config.set_error_reporting_consent_shown`.
  void markErrorReportingConsentShown() =>
      _update(state.copyWith(errorReportingConsentShown: true));

  /// Records the release [version] the user dismissed from the update banner.
  void setDismissedUpdateVersion(String version) =>
      _update(state.copyWith(dismissedUpdateVersion: version));

  /// Records the release [version] the user permanently skipped.
  void setSkippedUpdateVersion(String version) =>
      _update(state.copyWith(skippedUpdateVersion: version));

  /// Stamps the time (unix millis) of the last successful update check.
  void setLastUpdateCheckMs(int millis) =>
      _update(state.copyWith(lastUpdateCheckMs: millis));

  /// Persists the last selected [spaceId]/[channelId] so the next launch can
  /// restore it. No-op when unchanged. Mirrors the reference's
  /// `Config.set_last_space_id` / `set_last_channel_id`.
  void setLastSelection(String spaceId, String channelId) {
    if (state.lastSpaceId == spaceId && state.lastChannelId == channelId) {
      return;
    }
    _update(state.copyWith(lastSpaceId: spaceId, lastChannelId: channelId));
  }

  /// A sanitised snapshot of the current settings for export to a file. Strips
  /// the local MCP bearer [AccordSettings.mcpToken] — the only secret that lives
  /// in settings — mirroring the reference exporter's token/password stripping.
  Map<String, dynamic> exportJson() {
    final json = state.toJson();
    json.remove('mcpToken');
    return json;
  }

  /// Replaces the current settings with those decoded from an exported file,
  /// preserving the local MCP token (never imported, like the reference's
  /// blocked keys). Returns false when [json] isn't a usable settings map.
  bool importJson(Map<dynamic, dynamic> json) {
    if (json.isEmpty) return false;
    // Keep the current device's MCP token rather than importing one.
    final merged = <dynamic, dynamic>{...json, 'mcpToken': state.mcpToken};
    try {
      _update(AccordSettings.fromJson(merged));
      return true;
    } catch (_) {
      return false;
    }
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
