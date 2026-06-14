import '../utils/json_utils.dart';

/// A DM call-signaling event (`call.ring` / `call.decline` / `call.cancel` /
/// `call.end`). These are emitted by the server to the participants of a DM or
/// group-DM channel so the client can drive ring / accept / decline / hang-up
/// UI. Accepting a call is implicit — the callee simply joins voice, which
/// produces the usual `voice.state_update`.
///
/// The payloads differ slightly per event: `call.ring` carries [callerId] plus
/// the full [participants] list (and optional [metadata]), while the others
/// carry the acting [userId]. Absent fields are left null.
class AccordCallSignal {
  /// The event type without the `call.` prefix: `ring`, `decline`, `cancel`,
  /// or `end`.
  final String type;
  final String channelId;

  /// The user who started ringing (`call.ring` only).
  final String? callerId;

  /// The user who acted on the call (`call.decline` / `call.cancel` /
  /// `call.end`).
  final String? userId;

  /// The DM participants the call targets (`call.ring`).
  final List<String> participants;

  /// Optional free-form payload echoed from the caller (e.g. ringtone hints).
  final Map<String, dynamic>? metadata;

  const AccordCallSignal({
    this.type = '',
    this.channelId = '',
    this.callerId,
    this.userId,
    this.participants = const [],
    this.metadata,
  });

  factory AccordCallSignal.fromJson(Map<String, dynamic> d,
      {String type = ''}) {
    return AccordCallSignal(
      type: type,
      channelId: asString(d['channel_id']),
      callerId: asStringOrNull(d['caller_id']),
      userId: asStringOrNull(d['user_id']),
      participants: [
        for (final p in asList(d['participants']) ?? const []) asString(p),
      ],
      metadata: asMap(d['metadata']),
    );
  }

  Map<String, dynamic> toJson() {
    final d = <String, dynamic>{
      'type': type,
      'channel_id': channelId,
    };
    if (callerId != null) d['caller_id'] = callerId;
    if (userId != null) d['user_id'] = userId;
    if (participants.isNotEmpty) d['participants'] = participants;
    if (metadata != null) d['metadata'] = metadata;
    return d;
  }
}
