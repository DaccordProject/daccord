/// Shared flatten/diff logic behind the two drag-reorder surfaces (the
/// sidebar's inline drag list and the bulk reorder dialog). The surfaces keep
/// their own drag semantics — what happens *during* a drag differs (the sidebar
/// carries a category's children along and reparents only the moved entry; the
/// dialog reparents every entry from the list order) — but the list
/// construction and the changed-position diff are identical.
library;

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/channels/utils/channel_sort.dart';

/// One row of a flattened reorder list: a category, or a channel carrying its
/// (mutable) parent category id.
class ChannelReorderEntry {
  ChannelReorderEntry.category(this.channel)
    : isCategory = true,
      parentId = null;
  ChannelReorderEntry.channel(this.channel, {required this.parentId})
    : isCategory = false;

  final AccordChannel channel;
  final bool isCategory;
  String? parentId;
}

/// A pending PATCH from a reorder: the channel's new position and, when it
/// crossed a category boundary, its new parent.
class ChannelPositionUpdate {
  const ChannelPositionUpdate(
    this.channelId, {
    required this.position,
    this.parentId,
    this.includeParent = false,
  });

  final String channelId;
  final int position;
  final String? parentId;
  final bool includeParent;

  /// The `channels.update` PATCH body for this change.
  Map<String, dynamic> toBody() => <String, dynamic>{
    'position': position,
    if (includeParent) 'parent_id': parentId,
  };
}

/// Builds the flat reorder list: each category followed by its children, with
/// uncategorized channels grouped before the categories when
/// [uncategorizedFirst] (the sidebar's layout) or after them otherwise (the
/// reorder dialog's). Order within each group follows `position`.
List<ChannelReorderEntry> flattenChannelsForReorder(
  List<AccordChannel> channels, {
  required bool uncategorizedFirst,
}) {
  final sorted = [
    ...channels,
  ]..sort((a, b) => parseChannelPosition(a).compareTo(parseChannelPosition(b)));
  final categories = sorted.where((c) => c.type == 'category').toList();
  final leaves = sorted.where((c) => c.type != 'category').toList();
  final byParent = <String?, List<AccordChannel>>{};
  for (final c in leaves) {
    byParent.putIfAbsent(c.parentId, () => []).add(c);
  }
  final uncategorized = [
    for (final c in byParent[null] ?? const <AccordChannel>[])
      ChannelReorderEntry.channel(c, parentId: null),
  ];
  final out = <ChannelReorderEntry>[];
  if (uncategorizedFirst) out.addAll(uncategorized);
  for (final category in categories) {
    out.add(ChannelReorderEntry.category(category));
    for (final child in byParent[category.id] ?? const <AccordChannel>[]) {
      out.add(ChannelReorderEntry.channel(child, parentId: category.id));
    }
  }
  if (!uncategorizedFirst) out.addAll(uncategorized);
  return out;
}

/// Walks the (reordered) [entries] and returns a PATCH for every channel whose
/// (parent, position) differs from the original. Positions count within each
/// bucket — categories share the top-level bucket; each category's children
/// share another — so siblings stay coherent.
List<ChannelPositionUpdate> diffChannelPositions(
  List<ChannelReorderEntry> entries,
) {
  final updates = <ChannelPositionUpdate>[];
  var categoryPos = 0;
  final childPos = <String?, int>{};
  for (final entry in entries) {
    final channel = entry.channel;
    if (entry.isCategory) {
      if (parseChannelPosition(channel) != categoryPos) {
        updates.add(ChannelPositionUpdate(channel.id, position: categoryPos));
      }
      categoryPos++;
    } else {
      final pos = childPos[entry.parentId] ?? 0;
      childPos[entry.parentId] = pos + 1;
      final parentChanged = channel.parentId != entry.parentId;
      final positionChanged = parseChannelPosition(channel) != pos;
      if (parentChanged || positionChanged) {
        updates.add(
          ChannelPositionUpdate(
            channel.id,
            position: pos,
            parentId: parentChanged ? entry.parentId : null,
            includeParent: parentChanged,
          ),
        );
      }
    }
  }
  return updates;
}
