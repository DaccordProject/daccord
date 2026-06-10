/// Payload for the `disconnected` event.
class DisconnectInfo {
  final int code;
  final String reason;
  const DisconnectInfo(this.code, this.reason);

  @override
  String toString() => 'DisconnectInfo(code: $code, reason: $reason)';
}

/// Payload for the `reconnecting` event.
class ReconnectInfo {
  final int attempt;
  final int maxAttempts;
  const ReconnectInfo(this.attempt, this.maxAttempts);

  @override
  String toString() =>
      'ReconnectInfo(attempt: $attempt, maxAttempts: $maxAttempts)';
}

/// A raw, undispatched gateway event (`type` + `data`). Emitted for every
/// event in addition to any typed stream.
class RawGatewayEvent {
  final String type;
  final Map<String, dynamic> data;
  const RawGatewayEvent(this.type, this.data);

  @override
  String toString() => 'RawGatewayEvent(type: $type)';
}
