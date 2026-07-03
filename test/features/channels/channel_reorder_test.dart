import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/channels/utils/channel_reorder.dart';
import 'package:flutter_test/flutter_test.dart';

AccordChannel _ch(
  String id, {
  required String type,
  Object? position,
  String? parentId,
}) {
  return AccordChannel(
    id: id,
    name: '#$id',
    type: type,
    position: position,
    parentId: parentId,
  );
}

void main() {
  group('flattenChannelsForReorder', () {
    final cat1 = _ch('cat1', type: 'category', position: 0);
    final cat2 = _ch('cat2', type: 'category', position: 1);
    final uncategorized = _ch('uncat', type: 'text', position: 0);
    final child1 = _ch('child1', type: 'text', position: 0, parentId: 'cat1');
    final child2 = _ch('child2', type: 'text', position: 1, parentId: 'cat1');
    final child3 = _ch('child3', type: 'text', position: 0, parentId: 'cat2');
    final channels = [cat2, child3, cat1, child2, uncategorized, child1];

    test('groups uncategorized channels before categories when requested', () {
      final result = flattenChannelsForReorder(
        channels,
        uncategorizedFirst: true,
      );
      expect(
        result.map((e) => e.channel.id),
        ['uncat', 'cat1', 'child1', 'child2', 'cat2', 'child3'],
      );
    });

    test('groups uncategorized channels after categories by default', () {
      final result = flattenChannelsForReorder(
        channels,
        uncategorizedFirst: false,
      );
      expect(
        result.map((e) => e.channel.id),
        ['cat1', 'child1', 'child2', 'cat2', 'child3', 'uncat'],
      );
    });

    test('marks categories and carries the parent id on children', () {
      final result = flattenChannelsForReorder(
        channels,
        uncategorizedFirst: true,
      );
      final byId = {for (final e in result) e.channel.id: e};
      expect(byId['cat1']!.isCategory, isTrue);
      expect(byId['cat1']!.parentId, isNull);
      expect(byId['child1']!.isCategory, isFalse);
      expect(byId['child1']!.parentId, 'cat1');
      expect(byId['uncat']!.isCategory, isFalse);
      expect(byId['uncat']!.parentId, isNull);
    });

    test('orders siblings by position within each bucket', () {
      final outOfOrderChild1 = _ch(
        'child1',
        type: 'text',
        position: 2,
        parentId: 'cat1',
      );
      final outOfOrderChild2 = _ch(
        'child2',
        type: 'text',
        position: 1,
        parentId: 'cat1',
      );
      final result = flattenChannelsForReorder(
        [cat1, outOfOrderChild1, outOfOrderChild2],
        uncategorizedFirst: true,
      );
      expect(
        result.map((e) => e.channel.id),
        ['cat1', 'child2', 'child1'],
      );
    });
  });

  group('diffChannelPositions', () {
    test('returns no updates when order matches existing positions', () {
      final cat1 = _ch('cat1', type: 'category', position: 0);
      final cat2 = _ch('cat2', type: 'category', position: 1);
      final child1 = _ch(
        'child1',
        type: 'text',
        position: 0,
        parentId: 'cat1',
      );
      final entries = [
        ChannelReorderEntry.category(cat1),
        ChannelReorderEntry.channel(child1, parentId: 'cat1'),
        ChannelReorderEntry.category(cat2),
      ];
      expect(diffChannelPositions(entries), isEmpty);
    });

    test('emits a position-only update when siblings are swapped', () {
      final cat1 = _ch('cat1', type: 'category', position: 0);
      final child1 = _ch(
        'child1',
        type: 'text',
        position: 0,
        parentId: 'cat1',
      );
      final child2 = _ch(
        'child2',
        type: 'text',
        position: 1,
        parentId: 'cat1',
      );
      // child2 now sorts before child1.
      final entries = [
        ChannelReorderEntry.category(cat1),
        ChannelReorderEntry.channel(child2, parentId: 'cat1'),
        ChannelReorderEntry.channel(child1, parentId: 'cat1'),
      ];
      final updates = diffChannelPositions(entries);
      expect(updates, hasLength(2));
      final byId = {for (final u in updates) u.channelId: u};
      expect(byId['child2']!.position, 0);
      expect(byId['child2']!.includeParent, isFalse);
      expect(byId['child1']!.position, 1);
      expect(byId['child1']!.includeParent, isFalse);
    });

    test('includes the new parent id when a channel crosses categories', () {
      final child1 = _ch(
        'child1',
        type: 'text',
        position: 0,
        parentId: 'cat1',
      );
      // Dragged from cat1 into cat2, landing at position 0.
      final entries = [
        ChannelReorderEntry.channel(child1, parentId: 'cat2'),
      ];
      final updates = diffChannelPositions(entries);
      expect(updates, hasLength(1));
      expect(updates.single.channelId, 'child1');
      expect(updates.single.position, 0);
      expect(updates.single.parentId, 'cat2');
      expect(updates.single.includeParent, isTrue);
      expect(updates.single.toBody(), {'position': 0, 'parent_id': 'cat2'});
    });

    test('toBody omits parent_id when the parent did not change', () {
      const update = ChannelPositionUpdate('child1', position: 2);
      expect(update.toBody(), {'position': 2});
    });
  });
}
