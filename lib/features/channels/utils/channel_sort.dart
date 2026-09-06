import 'package:accordkit/accordkit.dart';

/// Reads [AccordChannel.position] as an int. Missing/non-numeric values → 0.
int parseChannelPosition(AccordChannel c) => asInt(c.position);

/// A stable change-detection key for a channel list based on (id, parentId, position).
/// Sorting the parts ensures the signature is order-independent.
String channelListSignature(List<AccordChannel> channels) {
  final parts = [
    for (final c in channels) '${c.id}:${c.parentId}:${parseChannelPosition(c)}',
  ]..sort();
  return parts.join(',');
}
