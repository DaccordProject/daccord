import 'package:bonfire/features/messaging/utils/attachment_limits.dart';

/// The upload limits the connected Accord server actually enforces.
///
/// The server's limits are per-deployment configuration, not protocol
/// constants: `max_attachment_size` and `max_attachments_per_message` are rows
/// in `server_settings` that an admin can change at any time, checked on the
/// upload route.
///
/// These are read from `GET /settings` (the public, client-facing subset of
/// server settings) on connect, and fall back to [fallback] whenever the
/// request fails, the server is too old to expose them, or the values are
/// missing/nonsensical.
class AccordServerLimits {
  const AccordServerLimits({
    required this.maxAttachmentBytes,
    required this.maxAttachmentsPerMessage,
    this.fromServer = false,
  });

  /// Largest single attachment, in bytes (`settings.max_attachment_size`).
  final int maxAttachmentBytes;

  /// Most files allowed on one message
  /// (`settings.max_attachments_per_message`).
  final int maxAttachmentsPerMessage;

  /// Whether these came from the server or are the compiled-in [fallback].
  /// Only used for diagnostics/tests — the composer treats both the same.
  final bool fromServer;

  /// What the client assumes before (or instead of) hearing from the server.
  /// Matches the accordserver defaults, so a stock deployment behaves
  /// identically whether or not `GET /settings` succeeded.
  static const AccordServerLimits fallback = AccordServerLimits(
    maxAttachmentBytes: kMaxAttachmentBytes,
    maxAttachmentsPerMessage: kMaxAttachmentsPerMessage,
  );

  /// Reads the limits out of a `GET /settings` payload.
  ///
  /// Tolerant by design: a null map (request failed), a missing key (older
  /// server), a string-encoded number (JSON from a 64-bit column) and a
  /// zero/negative value all resolve to the [fallback] for that one field
  /// rather than failing the whole parse.
  factory AccordServerLimits.fromSettings(Map<String, dynamic>? settings) {
    if (settings == null) return fallback;
    final size = _positiveInt(settings['max_attachment_size']);
    final count = _positiveInt(settings['max_attachments_per_message']);
    if (size == null && count == null) return fallback;
    return AccordServerLimits(
      maxAttachmentBytes: size ?? fallback.maxAttachmentBytes,
      maxAttachmentsPerMessage: count ?? fallback.maxAttachmentsPerMessage,
      fromServer: true,
    );
  }

  static int? _positiveInt(Object? value) {
    // Deliberately not accordkit's `asInt`: that accepts bools (as 1/0) and
    // does not trim, so a server sending " 100 " would fall back silently.
    final parsed = switch (value) {
      final int v => v,
      final num v => v.toInt(),
      final String v => int.tryParse(v.trim()),
      _ => null,
    };
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  @override
  bool operator ==(Object other) =>
      other is AccordServerLimits &&
      other.maxAttachmentBytes == maxAttachmentBytes &&
      other.maxAttachmentsPerMessage == maxAttachmentsPerMessage &&
      other.fromServer == fromServer;

  @override
  int get hashCode =>
      Object.hash(maxAttachmentBytes, maxAttachmentsPerMessage, fromServer);

  @override
  String toString() =>
      'AccordServerLimits(maxAttachmentBytes: '
      '$maxAttachmentBytes, maxAttachmentsPerMessage: '
      '$maxAttachmentsPerMessage, fromServer: $fromServer)';
}
