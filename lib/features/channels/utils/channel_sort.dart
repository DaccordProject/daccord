import 'package:accordkit/accordkit.dart';

/// Reads [AccordChannel.position] as an int. Missing/non-numeric values → 0.
int parseChannelPosition(AccordChannel c) {
  final raw = c.position;
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw) ?? 0;
  return 0;
}

/// A stable change-detection key for a channel list based on (id, parentId, position).
/// Sorting the parts ensures the signature is order-independent.
String channelListSignature(List<AccordChannel> channels) {
  final parts = [
    for (final c in channels) '${c.id}:${c.parentId}:${parseChannelPosition(c)}',
  ]..sort();
  return parts.join(',');
}
