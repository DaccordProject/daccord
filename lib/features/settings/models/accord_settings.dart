import 'dart:math' as math;

import 'package:bonfire/features/spaces/models/space_folder.dart';
import 'package:bonfire/features/voice/utils/afk_logic.dart';
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

  /// Camera capture resolution labels, indexed by [videoResolution]. Mirrors the
  /// reference client's `config_voice.gd` `RESOLUTION_LABELS`.
  static const List<String> videoResolutionLabels = ['480p', '720p', '1080p'];

  /// Selectable camera frame rates, matching `config_voice.gd` `FPS_OPTIONS`.
  static const List<int> videoFpsOptions = [15, 30, 60];

  /// Screen-share capture resolution labels, indexed by [screenShareResolution].
  /// A separate ladder from the camera's: 480p is useless for sharing a desktop
  /// (UI text is unreadable), and sharing benefits from resolutions above what
  /// a webcam ever produces.
  static const List<String> screenShareResolutionLabels = [
    '720p',
    '1080p',
    '1440p',
  ];

  /// Selectable screen-share frame rates. Unlike the camera, this defaults to
  /// the top of the range — the common case for sharing is gameplay/video,
  /// where frame rate is what makes it look right.
  static const List<int> screenShareFpsOptions = [15, 30, 60];

  /// Default screen-share resolution index (720p). 720p60 costs roughly half
  /// the pixels/second of 1080p60, so it is the setting most machines and
  /// connections can actually sustain at 60 fps; users on better links can move
  /// up in Voice & Video settings.
  static const int defaultScreenShareResolution = 0;

  /// Default screen-share frame rate. Motion-friendly by default — see
  /// [screenShareFps].
  static const int defaultScreenShareFps = 60;

  /// Default port for the local Client MCP server. Mirrors the reference
  /// client's `config_developer.gd` `mcp_port` (39101).
  static const int defaultMcpPort = 39101;

  /// Tool groups the local MCP server may expose. Mirrors the reference
  /// client's groups, minus the Godot-specific `screenshot` group.
  static const List<String> mcpToolGroups = [
    'read',
    'navigate',
    'message',
    'moderate',
    'manage',
    'voice',
  ];

  /// Tool groups enabled by default when MCP is first turned on.
  static const List<String> defaultMcpAllowedGroups = ['read', 'navigate'];

  const AccordSettings({
    this.themePreset = AppThemePreset.dark,
    this.accentColor,
    this.notificationsEnabled = true,
    this.suppressEveryone = false,
    this.backgroundConnection = false,
    this.soundsEnabled = true,
    this.sfxVolume = 1.0,
    this.videoResolution = 1,
    this.videoFps = 30,
    this.screenShareResolution = defaultScreenShareResolution,
    this.screenShareFps = defaultScreenShareFps,
    this.screenShareMotionPriority = true,
    this.audioInputDeviceId = '',
    this.audioOutputDeviceId = '',
    this.videoInputDeviceId = '',
    this.inputVolume = 100,
    this.outputVolume = 100,
    this.inputSensitivity = 50,
    this.voiceAfkTimeoutMinutes = defaultAfkTimeoutMinutes,
    this.voiceAfkAutoMove = true,
    this.recentEmoji = const [],
    this.masterServerUrl = defaultMasterServerUrl,
    this.channelNotifications = const <String, String>{},
    this.acceptedRuleSpaces = const <String>[],
    this.acknowledgedNsfwChannels = const <String>[],
    this.collapsedCategories = const <String, List<String>>{},
    this.drafts = const <String, String>{},
    this.developerMode = false,
    this.mcpEnabled = false,
    this.mcpPort = defaultMcpPort,
    this.mcpToken = '',
    this.mcpAllowedGroups = defaultMcpAllowedGroups,
    this.autoUpdateCheck = true,
    this.dismissedUpdateVersion = '',
    this.skippedUpdateVersion = '',
    this.lastUpdateCheckMs = 0,
    this.lastSpaceId = '',
    this.lastChannelId = '',
    this.compactMode = false,
    this.convertEmoticons = true,
    this.reducedMotion = false,
    this.uiScale = 1.0,
    this.spaceOrder = const <String>[],
    this.spaceFolders = const <SpaceFolder>[],
    this.mutedSpaces = const <String>[],
    this.hiddenSpaces = const <String>[],
    this.channelListWidth = defaultChannelListWidth,
    this.errorReportingEnabled = false,
    this.errorReportingConsentShown = false,
  });

  /// Minimum / maximum UI text scale, matching the reference's `ui_scale` range.
  static const double minUiScale = 0.8;
  static const double maxUiScale = 1.4;

  /// Default / clamp range for the resizable channel-list column (desktop).
  static const double defaultChannelListWidth = 220;
  static const double minChannelListWidth = 180;
  static const double maxChannelListWidth = 420;

  /// Selected colour theme.
  final AppThemePreset themePreset;

  /// Optional accent (primary) override as an ARGB int; null = preset default.
  final int? accentColor;

  /// Whether to show local notifications for mentions.
  final bool notificationsEnabled;

  /// When true, `@everyone` mentions never raise a notification.
  final bool suppressEveryone;

  /// Android only: run a foreground service while backgrounded so the gateway
  /// connection (and with it message delivery + notifications) survives the
  /// OS freezing the app. Off by default — it shows a persistent notification
  /// and costs battery.
  final bool backgroundConnection;

  /// Whether to play SFX (message sent/received, mentions).
  final bool soundsEnabled;

  /// SFX playback volume, 0.0–1.0.
  final double sfxVolume;

  /// Camera capture resolution index into [videoResolutionLabels]
  /// (0 = 480p, 1 = 720p, 2 = 1080p).
  final int videoResolution;

  /// Camera capture frame rate (one of [videoFpsOptions]).
  final int videoFps;

  /// Screen-share capture resolution index into [screenShareResolutionLabels]
  /// (0 = 720p, 1 = 1080p, 2 = 1440p). Independent of [videoResolution]: a
  /// webcam and a shared game screen have nothing in common as encoder input.
  final int screenShareResolution;

  /// Screen-share capture frame rate (one of [screenShareFpsOptions]).
  /// Defaults to 60 — screen share is overwhelmingly used for games and video,
  /// and 30 fps is what made game streams look choppy (issue #151).
  final int screenShareFps;

  /// Whether the screen-share encoder should protect frame rate over
  /// resolution when it runs short of CPU or bandwidth (WebRTC's
  /// `maintainFramerate` degradation preference, plus a single non-simulcast
  /// layer). On = smooth motion for games/video; off = keeps every pixel sharp
  /// and drops frames instead, which is what you want for slides, code or
  /// anything mostly-static. Mirrors Discord's smoothness-vs-clarity choice.
  final bool screenShareMotionPriority;

  /// Selected microphone device ID (empty = system default). Applied to the
  /// LiveKit audio capture options. Mirrors `config_voice.gd` `input_device`.
  final String audioInputDeviceId;

  /// Selected speaker/output device ID (empty = system default; desktop only).
  /// Mirrors `config_voice.gd` `output_device`.
  final String audioOutputDeviceId;

  /// Selected camera device ID (empty = system default). Mirrors
  /// `config_voice.gd` `video_device`.
  final String videoInputDeviceId;

  /// Microphone input volume as a percentage, 0–200 (100 = unity). Mirrors
  /// `config_voice.gd` `input_volume`.
  final int inputVolume;

  /// Remote-audio output volume as a percentage, 0–200 (100 = unity). Mirrors
  /// `config_voice.gd` `output_volume`.
  final int outputVolume;

  /// Voice-activity sensitivity, 0–100. Higher = more sensitive (lower
  /// threshold). Mirrors `config_voice.gd` `input_sensitivity`.
  final int inputSensitivity;

  /// Minutes of inactivity (no keyboard/pointer input, no mic activity, app
  /// unfocused) before we mark ourselves AFK while connected to a voice
  /// channel. `0` turns AFK detection off. See
  /// `lib/features/voice/utils/afk_logic.dart`.
  final int voiceAfkTimeoutMinutes;

  /// Whether going AFK moves us into the space's designated AFK channel
  /// (`AccordSpace.afkChannelId`), when it defines one. The move is performed
  /// client-side by re-joining that channel — the Accord server has no
  /// move-participant route and never enforces `afk_channel_id` itself.
  final bool voiceAfkAutoMove;

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

  /// Whether Developer Mode is enabled (gates the local MCP server UI). Mirrors
  /// the reference client's `config_developer.gd` `developer/enabled`.
  final bool developerMode;

  /// Whether the local Client MCP server is enabled. Requires [developerMode].
  /// Mirrors `config_developer.gd` `mcp_enabled`.
  final bool mcpEnabled;

  /// TCP port the local MCP server binds on loopback. Mirrors `mcp_port`.
  final int mcpPort;

  /// Bearer token required by MCP clients. Generated locally, never sent to the
  /// Accord server. Mirrors `mcp_token`.
  final String mcpToken;

  /// Tool groups the MCP server exposes (subset of [mcpToolGroups]). Mirrors
  /// `mcp_allowed_groups`.
  final List<String> mcpAllowedGroups;

  /// Whether the app checks for new releases on startup. Mirrors the reference
  /// client's `Config.get_auto_update_check`.
  final bool autoUpdateCheck;

  /// The release version the user dismissed from the update banner, so it isn't
  /// shown again until a newer one ships. Mirrors the reference's dismissed
  /// version tracking.
  final String dismissedUpdateVersion;

  /// The release version the user permanently skipped (Skip this version).
  final String skippedUpdateVersion;

  /// Unix-millis of the last successful update check, used to throttle passive
  /// checks. Mirrors `Config.get_last_update_check` (which stores seconds).
  final int lastUpdateCheckMs;

  /// The space the user last had selected, restored on launch. Empty until a
  /// selection is made. Mirrors the reference's `Config` `last_space_id`.
  final String lastSpaceId;

  /// The channel the user last had selected, restored on launch (within
  /// [lastSpaceId]). Mirrors the reference's `last_channel_id`.
  final String lastChannelId;

  /// Compact message layout (tighter spacing, smaller avatars) vs the default
  /// cozy density. Mirrors the reference's layout-density setting.
  final bool compactMode;

  /// Whether text emoticons (`:)`, `<3`, `xD`, …) are replaced with the
  /// matching emoji when a message is sent or edited. On by default, matching
  /// Discord; see `applyEmoticons` in the messaging feature.
  final bool convertEmoticons;

  /// Reduces/disables UI animations (route transitions etc.). Mirrors
  /// `accessibility.reduced_motion`.
  final bool reducedMotion;

  /// App-wide text scale factor, clamped to [minUiScale]–[maxUiScale]. Mirrors
  /// `accessibility.ui_scale`.
  final double uiScale;

  /// Manual ordering of space icons in the rail, as an ordered list of space
  /// ids (across all servers). Spaces not listed render after, in server order.
  /// Mirrors the reference's `space_order`.
  final List<String> spaceOrder;

  /// User-defined rail folders. Mirrors the reference's `folders`.
  final List<SpaceFolder> spaceFolders;

  /// Space IDs the user has muted (per-space notification suppression). Stored
  /// client-side like [spaceFolders] — accordkit exposes no server-synced
  /// notification settings. Mirrors the old client's space "Mute Server" action.
  final List<String> mutedSpaces;

  /// Space IDs hidden from the rail *without leaving membership* — the local
  /// "Remove Server" action. The space stays joined on the server; it just isn't
  /// rendered until unhidden. Stored client-side like [spaceFolders].
  final List<String> hiddenSpaces;

  /// Width of the channel-list column on desktop, in logical pixels. Clamped to
  /// [minChannelListWidth]–[maxChannelListWidth]; persisted across restarts.
  final double channelListWidth;

  /// Opt-in anonymous crash/error reporting to GlitchTip. Off by default —
  /// nothing is sent until the user consents. Mirrors the reference client's
  /// `[error_reporting] enabled` config key.
  final bool errorReportingEnabled;

  /// Whether the first-launch consent dialog has been answered (in either
  /// direction), so it is never shown again. Mirrors the reference client's
  /// `[error_reporting] consent_shown`.
  final bool errorReportingConsentShown;

  AccordSettings copyWith({
    AppThemePreset? themePreset,
    int? accentColor,
    bool clearAccentColor = false,
    bool? notificationsEnabled,
    bool? suppressEveryone,
    bool? backgroundConnection,
    bool? soundsEnabled,
    double? sfxVolume,
    int? videoResolution,
    int? videoFps,
    int? screenShareResolution,
    int? screenShareFps,
    bool? screenShareMotionPriority,
    String? audioInputDeviceId,
    String? audioOutputDeviceId,
    String? videoInputDeviceId,
    int? inputVolume,
    int? outputVolume,
    int? inputSensitivity,
    int? voiceAfkTimeoutMinutes,
    bool? voiceAfkAutoMove,
    List<String>? recentEmoji,
    String? masterServerUrl,
    Map<String, String>? channelNotifications,
    List<String>? acceptedRuleSpaces,
    List<String>? acknowledgedNsfwChannels,
    Map<String, List<String>>? collapsedCategories,
    Map<String, String>? drafts,
    bool? developerMode,
    bool? mcpEnabled,
    int? mcpPort,
    String? mcpToken,
    List<String>? mcpAllowedGroups,
    bool? autoUpdateCheck,
    String? dismissedUpdateVersion,
    String? skippedUpdateVersion,
    int? lastUpdateCheckMs,
    String? lastSpaceId,
    String? lastChannelId,
    bool? compactMode,
    bool? convertEmoticons,
    bool? reducedMotion,
    double? uiScale,
    List<String>? spaceOrder,
    List<SpaceFolder>? spaceFolders,
    List<String>? mutedSpaces,
    List<String>? hiddenSpaces,
    double? channelListWidth,
    bool? errorReportingEnabled,
    bool? errorReportingConsentShown,
  }) {
    return AccordSettings(
      themePreset: themePreset ?? this.themePreset,
      accentColor: clearAccentColor ? null : (accentColor ?? this.accentColor),
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      suppressEveryone: suppressEveryone ?? this.suppressEveryone,
      backgroundConnection: backgroundConnection ?? this.backgroundConnection,
      soundsEnabled: soundsEnabled ?? this.soundsEnabled,
      sfxVolume: sfxVolume ?? this.sfxVolume,
      videoResolution: videoResolution ?? this.videoResolution,
      videoFps: videoFps ?? this.videoFps,
      screenShareResolution: screenShareResolution ?? this.screenShareResolution,
      screenShareFps: screenShareFps ?? this.screenShareFps,
      screenShareMotionPriority:
          screenShareMotionPriority ?? this.screenShareMotionPriority,
      audioInputDeviceId: audioInputDeviceId ?? this.audioInputDeviceId,
      audioOutputDeviceId: audioOutputDeviceId ?? this.audioOutputDeviceId,
      videoInputDeviceId: videoInputDeviceId ?? this.videoInputDeviceId,
      inputVolume: inputVolume ?? this.inputVolume,
      outputVolume: outputVolume ?? this.outputVolume,
      inputSensitivity: inputSensitivity ?? this.inputSensitivity,
      voiceAfkTimeoutMinutes:
          voiceAfkTimeoutMinutes ?? this.voiceAfkTimeoutMinutes,
      voiceAfkAutoMove: voiceAfkAutoMove ?? this.voiceAfkAutoMove,
      recentEmoji: recentEmoji ?? this.recentEmoji,
      masterServerUrl: masterServerUrl ?? this.masterServerUrl,
      channelNotifications: channelNotifications ?? this.channelNotifications,
      acceptedRuleSpaces: acceptedRuleSpaces ?? this.acceptedRuleSpaces,
      acknowledgedNsfwChannels:
          acknowledgedNsfwChannels ?? this.acknowledgedNsfwChannels,
      collapsedCategories: collapsedCategories ?? this.collapsedCategories,
      drafts: drafts ?? this.drafts,
      developerMode: developerMode ?? this.developerMode,
      mcpEnabled: mcpEnabled ?? this.mcpEnabled,
      mcpPort: mcpPort ?? this.mcpPort,
      mcpToken: mcpToken ?? this.mcpToken,
      mcpAllowedGroups: mcpAllowedGroups ?? this.mcpAllowedGroups,
      autoUpdateCheck: autoUpdateCheck ?? this.autoUpdateCheck,
      dismissedUpdateVersion:
          dismissedUpdateVersion ?? this.dismissedUpdateVersion,
      skippedUpdateVersion: skippedUpdateVersion ?? this.skippedUpdateVersion,
      lastUpdateCheckMs: lastUpdateCheckMs ?? this.lastUpdateCheckMs,
      lastSpaceId: lastSpaceId ?? this.lastSpaceId,
      lastChannelId: lastChannelId ?? this.lastChannelId,
      compactMode: compactMode ?? this.compactMode,
      convertEmoticons: convertEmoticons ?? this.convertEmoticons,
      reducedMotion: reducedMotion ?? this.reducedMotion,
      uiScale: uiScale ?? this.uiScale,
      spaceOrder: spaceOrder ?? this.spaceOrder,
      spaceFolders: spaceFolders ?? this.spaceFolders,
      mutedSpaces: mutedSpaces ?? this.mutedSpaces,
      hiddenSpaces: hiddenSpaces ?? this.hiddenSpaces,
      channelListWidth: channelListWidth ?? this.channelListWidth,
      errorReportingEnabled:
          errorReportingEnabled ?? this.errorReportingEnabled,
      errorReportingConsentShown:
          errorReportingConsentShown ?? this.errorReportingConsentShown,
    );
  }

  /// Whether [spaceId]'s notifications are muted.
  bool isSpaceMuted(String spaceId) => mutedSpaces.contains(spaceId);

  /// Whether [spaceId] is hidden from the rail (still joined on the server).
  bool isSpaceHidden(String spaceId) => hiddenSpaces.contains(spaceId);

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

  /// Camera capture dimensions (width, height) for the selected
  /// [videoResolution].
  (int, int) get videoDimensions {
    switch (videoResolution) {
      case 0:
        return (854, 480);
      case 2:
        return (1920, 1080);
      default:
        return (1280, 720);
    }
  }

  /// Screen-share capture dimensions (width, height) for the selected
  /// [screenShareResolution].
  (int, int) get screenShareDimensions {
    switch (screenShareResolution) {
      case 1:
        return (1920, 1080);
      case 2:
        return (2560, 1440);
      default:
        return (1280, 720);
    }
  }

  /// Voice-activity speaking threshold (0–1, compared against the LiveKit
  /// audio level) derived from [inputSensitivity]. Logarithmic mapping matching
  /// `config_voice.gd`: 0% → 0.1, 50% → ~0.003, 100% → 0.0001.
  double get speakingThreshold =>
      math.pow(10.0, -1.0 - 3.0 * inputSensitivity / 100.0).toDouble();

  /// Suggested max bitrate (bits/sec) for the selected [videoResolution],
  /// matching LiveKit's 16:9 capture presets.
  int get videoBitrate {
    switch (videoResolution) {
      case 0:
        return 500000;
      case 2:
        return 3000000;
      default:
        return 1700000;
    }
  }

  /// Suggested max send bitrate (bits/sec) for the current screen-share
  /// resolution + frame rate.
  ///
  /// Deliberately far above [videoBitrate]. Those are LiveKit's *camera*
  /// presets (720p → 1.7 Mbps), tuned for a soft, low-detail, slow-moving
  /// talking head; gameplay is full-frame motion with hard edges, and the same
  /// bitrate turns it into a blocky smear. LiveKit's built-in *screen-share*
  /// presets are no help either — they assume slides and IDEs, so they cap
  /// 720p at 800 kbps @ 5 fps and 1080p at 2.5 Mbps @ 15 fps.
  ///
  /// The 60 fps numbers below are the low end of what the live-streaming
  /// industry publishes for high-motion content: Twitch recommends 3,000–4,500
  /// kbps for 720p60 and 4,500–6,000 kbps for 1080p60; YouTube recommends
  /// 4,500 and 7,500 kbps respectively; Discord's screen-share tiers span
  /// roughly 2.5–8 Mbps over the same resolutions. We take the bottom of those
  /// ranges rather than the top because WebRTC encodes live (no lookahead or
  /// two-pass to spend the extra bits well) and the SFU has to relay the stream
  /// to every viewer in the channel.
  ///
  /// Frame rate scales the ceiling sub-linearly — halving the frame rate does
  /// not halve the bits needed, since consecutive frames are then less
  /// correlated and each costs more.
  int get screenShareBitrate {
    final base = switch (screenShareResolution) {
      1 => 6000000, // 1080p60
      2 => 9000000, // 1440p60
      _ => 3000000, // 720p60
    };
    final scale = screenShareFps <= 15
        ? 0.5
        : screenShareFps <= 30
        ? 0.7
        : 1.0;
    return (base * scale).round();
  }

  /// Returns the level set for [channelId], or null when the user hasn't
  /// overridden it (callers fall back to the default mention-only behaviour).
  String? channelNotificationLevel(String channelId) =>
      channelNotifications[channelId];

  Map<String, dynamic> toJson() => {
    'themePreset': themePreset.name,
    'accentColor': accentColor,
    'notificationsEnabled': notificationsEnabled,
    'suppressEveryone': suppressEveryone,
    'backgroundConnection': backgroundConnection,
    'soundsEnabled': soundsEnabled,
    'sfxVolume': sfxVolume,
    'videoResolution': videoResolution,
    'videoFps': videoFps,
    'screenShareResolution': screenShareResolution,
    'screenShareFps': screenShareFps,
    'screenShareMotionPriority': screenShareMotionPriority,
    'audioInputDeviceId': audioInputDeviceId,
    'audioOutputDeviceId': audioOutputDeviceId,
    'videoInputDeviceId': videoInputDeviceId,
    'inputVolume': inputVolume,
    'outputVolume': outputVolume,
    'inputSensitivity': inputSensitivity,
    'voiceAfkTimeoutMinutes': voiceAfkTimeoutMinutes,
    'voiceAfkAutoMove': voiceAfkAutoMove,
    'recentEmoji': recentEmoji,
    'masterServerUrl': masterServerUrl,
    'channelNotifications': channelNotifications,
    'acceptedRuleSpaces': acceptedRuleSpaces,
    'acknowledgedNsfwChannels': acknowledgedNsfwChannels,
    'collapsedCategories': collapsedCategories,
    'drafts': drafts,
    'developerMode': developerMode,
    'mcpEnabled': mcpEnabled,
    'mcpPort': mcpPort,
    'mcpToken': mcpToken,
    'mcpAllowedGroups': mcpAllowedGroups,
    'autoUpdateCheck': autoUpdateCheck,
    'dismissedUpdateVersion': dismissedUpdateVersion,
    'skippedUpdateVersion': skippedUpdateVersion,
    'lastUpdateCheckMs': lastUpdateCheckMs,
    'lastSpaceId': lastSpaceId,
    'lastChannelId': lastChannelId,
    'compactMode': compactMode,
    'convertEmoticons': convertEmoticons,
    'reducedMotion': reducedMotion,
    'uiScale': uiScale,
    'spaceOrder': spaceOrder,
    'spaceFolders': [for (final f in spaceFolders) f.toJson()],
    'mutedSpaces': mutedSpaces,
    'hiddenSpaces': hiddenSpaces,
    'channelListWidth': channelListWidth,
    'errorReportingEnabled': errorReportingEnabled,
    'errorReportingConsentShown': errorReportingConsentShown,
  };

  factory AccordSettings.fromJson(Map<dynamic, dynamic> json) {
    final master = (json['masterServerUrl'] as String?)?.trim();
    return AccordSettings(
      themePreset: AppThemePreset.fromName(json['themePreset'] as String?),
      accentColor: (json['accentColor'] as num?)?.toInt(),
      notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
      suppressEveryone: json['suppressEveryone'] as bool? ?? false,
      backgroundConnection: json['backgroundConnection'] as bool? ?? false,
      soundsEnabled: json['soundsEnabled'] as bool? ?? true,
      sfxVolume: (json['sfxVolume'] as num?)?.toDouble() ?? 1.0,
      videoResolution: (json['videoResolution'] as num?)?.toInt() ?? 1,
      videoFps: (json['videoFps'] as num?)?.toInt() ?? 30,
      // Screen-share quality landed after these settings shipped, so existing
      // installs have no keys here. They fall back to the motion-friendly
      // defaults rather than inheriting the camera values that made game
      // streams choppy in the first place (issue #151).
      screenShareResolution:
          (json['screenShareResolution'] as num?)?.toInt().clamp(
            0,
            screenShareResolutionLabels.length - 1,
          ) ??
          defaultScreenShareResolution,
      screenShareFps: screenShareFpsOptions.contains(
        (json['screenShareFps'] as num?)?.toInt(),
      )
          ? (json['screenShareFps'] as num).toInt()
          : defaultScreenShareFps,
      screenShareMotionPriority:
          json['screenShareMotionPriority'] as bool? ?? true,
      audioInputDeviceId: (json['audioInputDeviceId'] as String?) ?? '',
      audioOutputDeviceId: (json['audioOutputDeviceId'] as String?) ?? '',
      videoInputDeviceId: (json['videoInputDeviceId'] as String?) ?? '',
      inputVolume: (json['inputVolume'] as num?)?.toInt() ?? 100,
      outputVolume: (json['outputVolume'] as num?)?.toInt() ?? 100,
      inputSensitivity: (json['inputSensitivity'] as num?)?.toInt() ?? 50,
      voiceAfkTimeoutMinutes:
          (json['voiceAfkTimeoutMinutes'] as num?)?.toInt() ??
          defaultAfkTimeoutMinutes,
      voiceAfkAutoMove: json['voiceAfkAutoMove'] as bool? ?? true,
      recentEmoji: [
        for (final e in (json['recentEmoji'] as List? ?? const []))
          e.toString(),
      ],
      masterServerUrl: (master == null || master.isEmpty)
          ? defaultMasterServerUrl
          : master,
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
      developerMode: json['developerMode'] as bool? ?? false,
      mcpEnabled: json['mcpEnabled'] as bool? ?? false,
      mcpPort: (json['mcpPort'] as num?)?.toInt() ?? defaultMcpPort,
      mcpToken: (json['mcpToken'] as String?) ?? '',
      mcpAllowedGroups: json.containsKey('mcpAllowedGroups')
          ? [
              for (final g in (json['mcpAllowedGroups'] as List? ?? const []))
                g.toString(),
            ]
          : defaultMcpAllowedGroups,
      autoUpdateCheck: json['autoUpdateCheck'] as bool? ?? true,
      dismissedUpdateVersion: (json['dismissedUpdateVersion'] as String?) ?? '',
      skippedUpdateVersion: (json['skippedUpdateVersion'] as String?) ?? '',
      lastUpdateCheckMs: (json['lastUpdateCheckMs'] as num?)?.toInt() ?? 0,
      lastSpaceId: (json['lastSpaceId'] as String?) ?? '',
      lastChannelId: (json['lastChannelId'] as String?) ?? '',
      compactMode: json['compactMode'] as bool? ?? false,
      convertEmoticons: json['convertEmoticons'] as bool? ?? true,
      reducedMotion: json['reducedMotion'] as bool? ?? false,
      uiScale:
          (json['uiScale'] as num?)?.toDouble().clamp(minUiScale, maxUiScale) ??
          1.0,
      spaceOrder: [
        for (final s in (json['spaceOrder'] as List? ?? const [])) s.toString(),
      ],
      spaceFolders: [
        for (final f in (json['spaceFolders'] as List? ?? const []))
          if (f is Map) SpaceFolder.fromJson(f),
      ],
      mutedSpaces: [
        for (final s in (json['mutedSpaces'] as List? ?? const []))
          s.toString(),
      ],
      hiddenSpaces: [
        for (final s in (json['hiddenSpaces'] as List? ?? const []))
          s.toString(),
      ],
      channelListWidth:
          (json['channelListWidth'] as num?)?.toDouble().clamp(
            minChannelListWidth,
            maxChannelListWidth,
          ) ??
          defaultChannelListWidth,
      errorReportingEnabled: json['errorReportingEnabled'] as bool? ?? false,
      errorReportingConsentShown:
          json['errorReportingConsentShown'] as bool? ?? false,
    );
  }
}
