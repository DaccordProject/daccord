import 'dart:math';

import 'package:bonfire/features/profiles/services/profile_store.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/spaces/models/space_folder.dart';
import 'package:bonfire/features/voice/utils/afk_logic.dart';
import 'package:bonfire/shared/models/server_entity_key.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'settings.g.dart';

/// Local client preferences (theme, notifications, recent emoji), persisted to
/// the `accord-settings` Hive box (opened in `setupHive`). Watched by `main`
/// to build the active [ThemeData] and by the notification + emoji layers.
@Riverpod(keepAlive: true)
class SettingsController extends _$SettingsController {
  static const _key = 'settings';
  static const _maxRecentEmoji = 24;

  @override
  AccordSettings build() {
    final box = ProfileStore.settingsBox;
    final raw = box.get(_key);
    if (raw is Map) return AccordSettings.fromJson(raw);
    return const AccordSettings();
  }

  void _update(AccordSettings next) {
    state = next;
    ProfileStore.settingsBox.put(_key, next.toJson());
  }

  /// Claims settings written before server-qualified keys existed for the
  /// active server and persists the migration exactly once.
  ///
  /// A bare ID cannot be assigned to every connected server without leaking a
  /// draft, gate acknowledgement, or rail preference across ID collisions. The
  /// active server is the only conservative owner we can infer, so the first
  /// activation rewrites all legacy entries to that server and removes the
  /// ambiguous forms.
  void claimLegacyEntityKeys(String serverKey) {
    String scoped(String value) => ServerEntityKey.tryDecode(value) == null
        ? ServerEntityKey(serverKey, value).encoded
        : value;

    Map<String, T> scopedMap<T>(Map<String, T> source) => {
      for (final entry in source.entries) scoped(entry.key): entry.value,
    };

    final hasLegacy = <Iterable<String>>[
      state.channelNotifications.keys,
      state.acceptedRuleSpaces,
      state.acknowledgedNsfwChannels,
      state.collapsedCategories.keys,
      state.collapsedCategories.values.expand((ids) => ids),
      state.drafts.keys,
      state.spaceOrder,
      state.spaceFolders.expand((folder) => folder.spaceIds),
      state.mutedSpaces,
      state.hiddenSpaces,
      [state.lastSpaceId, state.lastChannelId].where((id) => id.isNotEmpty),
    ].expand((ids) => ids).any((id) => ServerEntityKey.tryDecode(id) == null);
    if (!hasLegacy) return;

    _update(
      state.copyWith(
        channelNotifications: scopedMap(state.channelNotifications),
        acceptedRuleSpaces: state.acceptedRuleSpaces.map(scoped).toList(),
        acknowledgedNsfwChannels: state.acknowledgedNsfwChannels
            .map(scoped)
            .toList(),
        collapsedCategories: {
          for (final entry in state.collapsedCategories.entries)
            scoped(entry.key): entry.value.map(scoped).toList(),
        },
        drafts: scopedMap(state.drafts),
        spaceOrder: state.spaceOrder.map(scoped).toList(),
        spaceFolders: [
          for (final folder in state.spaceFolders)
            folder.copyWith(spaceIds: folder.spaceIds.map(scoped).toList()),
        ],
        mutedSpaces: state.mutedSpaces.map(scoped).toList(),
        hiddenSpaces: state.hiddenSpaces.map(scoped).toList(),
        lastSpaceId: state.lastSpaceId.isEmpty ? '' : scoped(state.lastSpaceId),
        lastChannelId: state.lastChannelId.isEmpty
            ? ''
            : scoped(state.lastChannelId),
      ),
    );
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

  /// Sets the screen-share capture resolution index (0 = 720p, 1 = 1080p,
  /// 2 = 1440p). Independent of the camera resolution.
  void setScreenShareResolution(int index) => _update(
    state.copyWith(
      screenShareResolution: index.clamp(
        0,
        AccordSettings.screenShareResolutionLabels.length - 1,
      ),
    ),
  );

  /// Sets the screen-share frame rate; ignored when not one of
  /// [AccordSettings.screenShareFpsOptions].
  void setScreenShareFps(int fps) {
    if (!AccordSettings.screenShareFpsOptions.contains(fps)) return;
    _update(state.copyWith(screenShareFps: fps));
  }

  /// Toggles "prioritise smooth motion" for screen share (frame rate protected
  /// over resolution when the encoder runs short).
  void setScreenShareMotionPriority(bool enabled) =>
      _update(state.copyWith(screenShareMotionPriority: enabled));

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
  void setChannelNotificationLevel(
    String serverKey,
    String channelId,
    String? level,
  ) {
    final key = ServerEntityKey(serverKey, channelId).encoded;
    final next = Map<String, String>.from(state.channelNotifications);
    if (level == null || level.isEmpty) {
      if (!next.containsKey(key)) return;
      next.remove(key);
    } else {
      if (next[key] == level) return;
      next[key] = level;
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
  void setSpaceOrder(List<ServerEntityKey> order) => _update(
    state.copyWith(spaceOrder: [for (final key in order) key.encoded]),
  );

  /// Creates a folder containing [spaceIds] and returns its id.
  String createFolder({
    String name = '',
    List<ServerEntityKey> spaces = const [],
  }) {
    final spaceIds = [for (final key in spaces) key.encoded];
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
  void moveSpaceToFolder(
    ServerEntityKey space,
    String? folderId, {
    ServerEntityKey? before,
  }) {
    final spaceId = space.encoded;
    final beforeId = before?.encoded;
    final next = <SpaceFolder>[];
    for (final f in state.spaceFolders) {
      var ids = [
        for (final s in f.spaceIds)
          if (s != spaceId) s,
      ];
      if (f.id == folderId) {
        final at = beforeId == null ? -1 : ids.indexOf(beforeId);
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
  void setSpaceMuted(String serverKey, String spaceId, bool muted) {
    final key = ServerEntityKey(serverKey, spaceId).encoded;
    final isMuted = state.mutedSpaces.contains(key);
    if (muted == isMuted) return;
    _update(
      state.copyWith(
        mutedSpaces: muted
            ? [...state.mutedSpaces, key]
            : [
                for (final s in state.mutedSpaces)
                  if (s != key) s,
              ],
      ),
    );
  }

  /// Toggles the muted state of [spaceId].
  void toggleSpaceMuted(String serverKey, String spaceId) => setSpaceMuted(
    serverKey,
    spaceId,
    !state.isSpaceMuted(serverKey, spaceId),
  );

  /// Hides [spaceId] from the rail without leaving it, or restores it. No-op
  /// when already in the requested state.
  void setSpaceHidden(String serverKey, String spaceId, bool hidden) {
    final key = ServerEntityKey(serverKey, spaceId).encoded;
    final isHidden = state.hiddenSpaces.contains(key);
    if (hidden == isHidden) return;
    _update(
      state.copyWith(
        hiddenSpaces: hidden
            ? [...state.hiddenSpaces, key]
            : [
                for (final s in state.hiddenSpaces)
                  if (s != key) s,
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
    if (next.length > _maxRecentEmoji) {
      next.removeRange(_maxRecentEmoji, next.length);
    }
    _update(state.copyWith(recentEmoji: next));
  }

  /// Marks [spaceId]'s rules interstitial as accepted so it isn't reshown.
  void acceptRules(String serverKey, String spaceId) {
    final key = ServerEntityKey(serverKey, spaceId).encoded;
    if (state.acceptedRuleSpaces.contains(key)) return;
    _update(
      state.copyWith(acceptedRuleSpaces: [...state.acceptedRuleSpaces, key]),
    );
  }

  /// Marks [channelId]'s NSFW gate as acknowledged.
  void acknowledgeNsfw(String serverKey, String channelId) {
    final key = ServerEntityKey(serverKey, channelId).encoded;
    if (state.acknowledgedNsfwChannels.contains(key)) return;
    _update(
      state.copyWith(
        acknowledgedNsfwChannels: [...state.acknowledgedNsfwChannels, key],
      ),
    );
  }

  /// Sets whether [categoryId] is collapsed in [spaceId]'s channel list.
  void setCategoryCollapsed(
    String serverKey,
    String spaceId,
    String categoryId,
    bool collapsed,
  ) {
    final spaceKey = ServerEntityKey(serverKey, spaceId).encoded;
    final categoryKey = ServerEntityKey(serverKey, categoryId).encoded;
    final current = state.collapsedCategories[spaceKey] ?? const <String>[];
    final isCollapsed = current.contains(categoryKey);
    if (collapsed == isCollapsed) return;
    final nextList = collapsed
        ? [...current, categoryKey]
        : [
            for (final c in current)
              if (c != categoryKey) c,
          ];
    final next = Map<String, List<String>>.from(state.collapsedCategories);
    if (nextList.isEmpty) {
      next.remove(spaceKey);
    } else {
      next[spaceKey] = nextList;
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
    if (enabled && state.mcpToken.trim().isEmpty) {
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

  /// Records the release [version] the user permanently skipped.
  void setSkippedUpdateVersion(String version) =>
      _update(state.copyWith(skippedUpdateVersion: version));

  /// Stamps the time (unix millis) of the last successful update check.
  void setLastUpdateCheckMs(int millis) =>
      _update(state.copyWith(lastUpdateCheckMs: millis));

  /// Persists the last selected [spaceId]/[channelId] so the next launch can
  /// restore it. No-op when unchanged. Mirrors the reference's
  /// `Config.set_last_space_id` / `set_last_channel_id`.
  void setLastSelection(String serverKey, String spaceId, String channelId) {
    final spaceKey = ServerEntityKey(serverKey, spaceId).encoded;
    final channelKey = ServerEntityKey(serverKey, channelId).encoded;
    if (state.lastSpaceId == spaceKey && state.lastChannelId == channelKey) {
      return;
    }
    _update(state.copyWith(lastSpaceId: spaceKey, lastChannelId: channelKey));
  }

  /// A sanitised snapshot of the current settings for export to a file. Strips
  /// the local MCP bearer [AccordSettings.mcpToken] — the only secret that lives
  /// in settings — and disables its opt-in flags so restoring the backup cannot
  /// start a service. Mirrors the reference exporter's secret stripping.
  Map<String, dynamic> exportJson() {
    final json = state.toJson();
    json.remove('mcpToken');
    json['developerMode'] = false;
    json['mcpEnabled'] = false;
    return json;
  }

  /// Replaces the current settings with those decoded from an exported file,
  /// preserving an existing local MCP token (never importing one, like the
  /// reference's blocked keys). Developer Mode and MCP are always disabled so
  /// importing an old backup cannot start a local service. Returns false when
  /// [json] isn't a usable settings map.
  bool importJson(Map<dynamic, dynamic> json) {
    if (json.isEmpty) return false;
    final localToken = state.mcpToken.trim().isEmpty ? '' : state.mcpToken;
    final merged = <dynamic, dynamic>{
      ...json,
      'developerMode': false,
      'mcpEnabled': false,
      'mcpToken': localToken,
    };
    try {
      _update(AccordSettings.fromJson(merged));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Saves (or clears, when [text] is blank) the unsent draft for [channelId].
  void setDraft(String serverKey, String channelId, String text) {
    final key = ServerEntityKey(serverKey, channelId).encoded;
    final trimmed = text;
    final current = state.drafts[key] ?? '';
    if (current == trimmed) return;
    final next = Map<String, String>.from(state.drafts);
    if (trimmed.isEmpty) {
      next.remove(key);
    } else {
      next[key] = trimmed;
    }
    _update(state.copyWith(drafts: next));
  }
}
