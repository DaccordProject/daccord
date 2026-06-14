import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/notifications/controllers/sound.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'call.g.dart';

/// An incoming DM call awaiting accept/decline, driven by a `call.ring` gateway
/// event.
@immutable
class IncomingCall {
  const IncomingCall({
    required this.channelId,
    required this.callerId,
    required this.serverKey,
    this.participants = const [],
    this.video = false,
  });

  final String channelId;
  final String callerId;

  /// The connection (`userId@baseUrl`) the ring arrived on; the accept/decline
  /// REST calls must route back through this server's client.
  final String serverKey;
  final List<String> participants;

  /// Whether the caller started with video (a hint from the ring metadata).
  final bool video;
}

/// DM call signaling state: at most one pending incoming ring and, for the
/// caller, the channel we're currently ringing (before the callee answers).
@immutable
class CallState {
  const CallState({
    this.incoming,
    this.outgoingChannelId,
    this.endedMessage,
  });

  /// A ring we've received and not yet answered or dismissed.
  final IncomingCall? incoming;

  /// The DM channel we (as caller) are ringing; cleared once the callee joins,
  /// declines, or we cancel. Distinct from [VoiceController]'s channel — we're
  /// already connected to voice while this is set.
  final String? outgoingChannelId;

  /// Transient banner text (e.g. "Call declined"), cleared by the UI.
  final String? endedMessage;

  bool get hasOutgoing => outgoingChannelId != null;

  CallState copyWith({
    IncomingCall? incoming,
    bool clearIncoming = false,
    String? outgoingChannelId,
    bool clearOutgoing = false,
    String? endedMessage,
    bool clearEnded = false,
  }) {
    return CallState(
      incoming: clearIncoming ? null : (incoming ?? this.incoming),
      outgoingChannelId:
          clearOutgoing ? null : (outgoingChannelId ?? this.outgoingChannelId),
      endedMessage: clearEnded ? null : (endedMessage ?? this.endedMessage),
    );
  }
}

/// Orchestrates DM voice/video calls: placing an outgoing call (join voice +
/// `call/ring`), reacting to the `call.*` gateway events, and accepting or
/// declining an incoming ring. The actual media session is owned by
/// [VoiceController]; this controller layers the ring/accept/decline signaling
/// on top, mirroring how the server models a DM call as "voice join + signaling"
/// (accordserver #32).
@Riverpod(keepAlive: true)
class CallController extends _$CallController {
  @override
  CallState build() => const CallState();

  /// The client for [serverKey], or the active connection's client when null.
  AccordClient? _clientFor(String? serverKey) {
    final key = serverKey ?? ref.read(connectionsControllerProvider).activeKey;
    if (key == null) return null;
    return ref.read(accordAuthProvider.notifier).clientForKey(key);
  }

  /// Places an outgoing call on a DM/group-DM [channel]: joins voice, then rings
  /// the other participant(s). [video] starts the camera and hints the callee.
  Future<void> startCall(AccordChannel channel, {bool video = false}) async {
    final serverKey = ref.read(connectionsControllerProvider).activeKey;
    final client = _clientFor(serverKey);
    if (client == null) return;

    final voice = ref.read(voiceControllerProvider.notifier);
    await voice.join(channel.id, null);
    // Bail if the join failed (the voice controller surfaces its own error).
    if (ref.read(voiceControllerProvider).channelId != channel.id) return;

    if (video) await voice.toggleVideo();
    state = state.copyWith(outgoingChannelId: channel.id, clearEnded: true);
    await client.voice.ring(channel.id, metadata: {'video': video});
  }

  /// Accepts the pending incoming call by joining its voice channel (the server
  /// treats the join as the accept). Returns the channel id joined, or null.
  Future<String?> acceptIncoming() async {
    final incoming = state.incoming;
    if (incoming == null) return null;
    soundManager.stopRingtone();
    state = state.copyWith(clearIncoming: true);
    await ref
        .read(voiceControllerProvider.notifier)
        .join(incoming.channelId, null);
    return incoming.channelId;
  }

  /// Declines the pending incoming call, telling the caller over `call/decline`.
  Future<void> declineIncoming() async {
    final incoming = state.incoming;
    if (incoming == null) return;
    soundManager.stopRingtone();
    state = state.copyWith(clearIncoming: true);
    await _clientFor(incoming.serverKey)?.voice.declineCall(incoming.channelId);
  }

  /// Cancels an outgoing call we're still ringing on (callee hasn't answered):
  /// leaves voice and sends `call/cancel`. If already answered this just leaves.
  Future<void> cancelOutgoing() async {
    final channelId = state.outgoingChannelId;
    final voice = ref.read(voiceControllerProvider);
    final client = _clientFor(voice.serverKey);
    await ref.read(voiceControllerProvider.notifier).leave();
    if (channelId != null) {
      await client?.voice.cancelCall(channelId);
      state = state.copyWith(clearOutgoing: true);
    }
  }

  void clearEndedMessage() {
    if (state.endedMessage == null) return;
    state = state.copyWith(clearEnded: true);
  }

  // ── Gateway-driven transitions (called from the event handler) ────────────

  /// A `call.ring` arrived. Ignored if it's our own ring or we're already in the
  /// call; otherwise shows the incoming-call UI and starts the ringtone.
  void handleRing(AccordCallSignal sig, String serverKey, String myUserId) {
    if (sig.callerId == myUserId) return;
    if (ref.read(voiceControllerProvider).channelId == sig.channelId) return;
    // Already ringing for this channel — keep the existing prompt.
    if (state.incoming?.channelId == sig.channelId) return;
    state = state.copyWith(
      incoming: IncomingCall(
        channelId: sig.channelId,
        callerId: sig.callerId ?? '',
        serverKey: serverKey,
        participants: sig.participants,
        video: sig.metadata?['video'] == true,
      ),
    );
    soundManager.startRingtone();
  }

  /// A `call.decline` arrived. If it's for our outgoing call, end it locally and
  /// surface a "declined" banner.
  void handleDecline(AccordCallSignal sig) {
    if (state.outgoingChannelId != sig.channelId) return;
    ref.read(voiceControllerProvider.notifier).leave();
    state = state.copyWith(clearOutgoing: true, endedMessage: 'Call declined');
  }

  /// A `call.cancel` or `call.end` arrived — the caller hung up before we
  /// answered (or the room emptied). Dismiss any incoming ring for that channel.
  void handleCancelOrEnd(AccordCallSignal sig) {
    if (state.incoming?.channelId != sig.channelId) return;
    soundManager.stopRingtone();
    state = state.copyWith(clearIncoming: true);
  }

  /// A peer joined the channel we're ringing — the call connected, so drop the
  /// "Calling…" state. Driven by the voice-state cache in the event handler.
  void markAnswered(String channelId) {
    if (state.outgoingChannelId != channelId) return;
    state = state.copyWith(clearOutgoing: true);
  }
}
