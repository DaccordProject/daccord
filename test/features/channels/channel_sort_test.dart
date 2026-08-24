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

// Simulates `ReorderableListView.onReorderItem`, whose new index is already in
// post-removal coordinates. Mirrors the channel reorder surfaces.
List<T> _applyReorderItem<T>(List<T> items, int oldIndex, int newIndex) {
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

  group('onReorderItem index semantics', () {
    test('dropping in the original slot is a no-op', () {
      expect(_applyReorderItem(['A', 'B', 'C'], 0, 0), ['A', 'B', 'C']);
    });

    test('drag down by one slot', () {
      expect(_applyReorderItem(['A', 'B', 'C'], 0, 1), ['B', 'A', 'C']);
    });

    test('drag down to last position', () {
      expect(_applyReorderItem(['A', 'B', 'C', 'D'], 0, 3), [
        'B',
        'C',
        'D',
        'A',
      ]);
    });

    test('drag up by one slot', () {
      expect(_applyReorderItem(['A', 'B', 'C'], 2, 1), ['A', 'C', 'B']);
    });

    test('drag up to first position', () {
      expect(_applyReorderItem(['A', 'B', 'C', 'D'], 3, 0), [
        'D',
        'A',
        'B',
        'C',
      ]);
    });

    test('drag up multiple slots', () {
      expect(_applyReorderItem(['A', 'B', 'C', 'D'], 3, 1), [
        'A',
        'D',
        'B',
        'C',
      ]);
    });

    test('does not apply the legacy downward-index adjustment', () {
      expect(_applyReorderItem(['A', 'B', 'C', 'D'], 0, 2), [
        'B',
        'C',
        'A',
        'D',
      ]);
    });
  });
}
