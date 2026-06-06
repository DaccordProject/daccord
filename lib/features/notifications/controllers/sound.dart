import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';

/// Plays short UI sound effects (message sent/received, mentions). The Dart
/// analogue of the reference client's `SoundManager` autoload
/// (`../daccord/scripts/autoload/sound_manager.gd`), scoped to the non-voice
/// SFX — voice join/leave/mute/deafen are deferred with the rest of voice.
///
/// A global singleton ([soundManager]) rather than a Riverpod provider: it has
/// no observable state, and the call sites (event handler, composer) just fire
/// one-shot plays. Enablement/volume are mirrored from `AccordSettings` by
/// `MainWindow`.
class SoundManager {
  SoundManager._();

  /// Asset paths are resolved relative to `assets/` by audioplayers.
  static const _sounds = <String, String>{
    'message_received': 'sfx/message_received.wav',
    'mention_received': 'sfx/mention_received.wav',
    'message_sent': 'sfx/message_sent.wav',
    'member_join': 'sfx/message_received.wav',
  };

  static const _poolSize = 4;

  final List<AudioPlayer> _pool =
      List.generate(_poolSize, (_) => AudioPlayer());
  int _next = 0;
  bool _initialized = false;

  AppLifecycleListener? _lifecycle;

  /// Whether the app currently has focus. The generic `message_received` sound
  /// only plays while unfocused (mentions always play).
  bool focused = true;

  /// Mirrors `AccordSettings.soundsEnabled`.
  bool enabled = true;

  /// Mirrors `AccordSettings.sfxVolume` (0.0–1.0).
  double volume = 1.0;

  void init() {
    if (_initialized) return;
    _initialized = true;
    for (final player in _pool) {
      player.setReleaseMode(ReleaseMode.stop);
    }
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) => focused = state == AppLifecycleState.resumed,
    );
  }

  /// Plays the named SFX from [_sounds]. No-ops when disabled, muted, or the
  /// name is unknown.
  Future<void> play(String name) async {
    if (!enabled || volume <= 0.0) return;
    final asset = _sounds[name];
    if (asset == null) return;

    final player = _pool[_next];
    _next = (_next + 1) % _poolSize;
    await player.setVolume(volume.clamp(0.0, 1.0).toDouble());
    await player.play(AssetSource(asset));
  }

  /// Pure decision half of [playForMessage]: returns the SFX name to play, or
  /// null for silence — without touching audio. Extracted so the chime policy
  /// (mirroring the reference's `play_for_message`) can be unit-tested.
  ///
  /// [isMention] folds together direct, role, and `@everyone` mentions;
  /// [isVisibleChannel] is true when the message lands in the channel the user
  /// is currently looking at. [enabled]/[volume]/[focused] mirror the
  /// instance fields so the decision can be exercised with explicit state.
  static String? soundForMessage({
    required bool isMention,
    required bool isVisibleChannel,
    required bool focused,
    required bool enabled,
    required double volume,
    bool isMemberJoin = false,
  }) {
    // Disabled or muted: never chime, regardless of the message.
    if (!enabled || volume <= 0.0) return null;
    if (isMemberJoin) return 'member_join';
    // The currently-open channel never chimes (you can see the message).
    if (isVisibleChannel) return null;
    if (isMention) return 'mention_received';
    if (!focused) return 'message_received';
    return null;
  }

  /// Decides which SFX (if any) to play for an incoming message, then performs
  /// playback. The decision is delegated to the pure [soundForMessage].
  void playForMessage({
    required bool isMention,
    required bool isVisibleChannel,
    bool isMemberJoin = false,
  }) {
    final name = soundForMessage(
      isMention: isMention,
      isVisibleChannel: isVisibleChannel,
      focused: focused,
      enabled: enabled,
      volume: volume,
      isMemberJoin: isMemberJoin,
    );
    if (name != null) play(name);
  }

  void dispose() {
    _lifecycle?.dispose();
    for (final player in _pool) {
      player.dispose();
    }
  }
}

/// App-wide SFX player. Initialized in `main`, configured by `MainWindow`.
final soundManager = SoundManager._();
