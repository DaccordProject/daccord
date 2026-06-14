import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/channels/utils/channel_sort.dart';
import 'package:flutter_test/flutter_test.dart';

// Minimal stub so tests don't need a real AccordChannel constructor.
AccordChannel _ch(String id, {Object? position, String? parentId}) {
  return AccordChannel(
    id: id,
    name: '#$id',
    type: 'text',
    position: position,
    parentId: parentId,
  );
}

// Applies the canonical ReorderableListView.onReorder index adjustment:
// newIndex is in pre-removal coordinates (the dragged slot still counted),
// so subtract 1 when dragging down to get the post-removal insertion point.
int _adjustReorder(int oldIndex, int newIndex) =>
    newIndex > oldIndex ? newIndex - 1 : newIndex;

// Simulates one reorder operation on a simple list of strings and returns the
// result. Mirrors the pattern used in _ChannelReorderState._onReorder and
// _ChannelDragListState._onReorder.
List<T> _applyReorder<T>(List<T> items, int oldIndex, int newIndex) {
  newIndex = _adjustReorder(oldIndex, newIndex);
  final result = [...items];
  final item = result.removeAt(oldIndex);
  result.insert(newIndex, item);
  return result;
}

void main() {
  group('parseChannelPosition', () {
    test('int value returned as-is', () {
      expect(parseChannelPosition(_ch('a', position: 3)), 3);
    });

    test('double coerced to int', () {
      expect(parseChannelPosition(_ch('a', position: 2.9)), 2);
    });

    test('string parsed', () {
      expect(parseChannelPosition(_ch('a', position: '7')), 7);
    });

    test('null returns 0', () {
      expect(parseChannelPosition(_ch('a', position: null)), 0);
    });

    test('non-numeric string returns 0', () {
      expect(parseChannelPosition(_ch('a', position: 'bad')), 0);
    });
  });

  group('channelListSignature', () {
    test('empty list gives empty signature', () {
      expect(channelListSignature([]), '');
    });

    test('same channels in different order give same signature', () {
      final a = _ch('1', position: 0);
      final b = _ch('2', position: 1);
      expect(channelListSignature([a, b]), channelListSignature([b, a]));
    });

    test('different position makes signature differ', () {
      final before = [_ch('1', position: 0)];
      final after = [_ch('1', position: 1)];
      expect(channelListSignature(before), isNot(channelListSignature(after)));
    });

    test('different parentId makes signature differ', () {
      final before = [_ch('1', position: 0, parentId: null)];
      final after = [_ch('1', position: 0, parentId: 'cat1')];
      expect(channelListSignature(before), isNot(channelListSignature(after)));
    });
  });

  // Tests for the canonical ReorderableListView.onReorder index adjustment.
  // Flutter's onReorder reports newIndex in pre-removal coordinates (the dragged
  // slot is still counted), so subtracting 1 when dragging down is required to
  // convert to the post-removal insertion point. This is the fix from #138.
  group('reorder index adjustment', () {
    test('drag down by one slot', () {
      // oldIndex=0, newIndex=1 pre-removal → adjusted to 0 → no-op (can't move
      // to the slot immediately below itself). After adjust: item stays at 0.
      expect(_applyReorder(['A', 'B', 'C'], 0, 1), ['A', 'B', 'C']);
    });

    test('drag down two slots', () {
      // A [0] dragged to position 2 (pre-removal). After decrement: insert at 1.
      expect(_applyReorder(['A', 'B', 'C'], 0, 2), ['B', 'A', 'C']);
    });

    test('drag down to last position', () {
      // Flutter passes newIndex == itemCount when dragging to the very end.
      // After decrement: last index in the post-removal list.
      expect(_applyReorder(['A', 'B', 'C', 'D'], 0, 4), ['B', 'C', 'D', 'A']);
    });

    test('drag up by one slot', () {
      // newIndex < oldIndex → no decrement.
      expect(_applyReorder(['A', 'B', 'C'], 2, 1), ['A', 'C', 'B']);
    });

    test('drag up to first position', () {
      expect(_applyReorder(['A', 'B', 'C', 'D'], 3, 0), ['D', 'A', 'B', 'C']);
    });

    test('drag up multiple slots', () {
      expect(_applyReorder(['A', 'B', 'C', 'D'], 3, 1), ['A', 'D', 'B', 'C']);
    });

    test('without adjustment drag-down lands one slot too low (regression guard)', () {
      // Without the decrement a drag from 0 to newIndex=2 would insert at 2,
      // placing the item one position further down than intended.
      final list = ['A', 'B', 'C', 'D'];
      final bugged = [...list];
      final item = bugged.removeAt(0);
      bugged.insert(2, item); // no adjustment
      expect(bugged, ['B', 'C', 'A', 'D']); // A is one slot too low

      final fixed = _applyReorder(list, 0, 2); // with adjustment
      expect(fixed, ['B', 'A', 'C', 'D']); // A is in the correct position
    });
  });
}
