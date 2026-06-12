import 'dart:io';

import 'package:bonfire/features/server/utils/space_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

// ignore: depend_on_referenced_packages
import 'package:accordkit/accordkit.dart';

AccordSpace _space(String id, String name) => AccordSpace(id: id, name: name);

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('space_cache_test_');
    Hive.init(tempDir.path);
    await Hive.openBox<dynamic>(SpaceCache.boxName);
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('SpaceCache.save / load round-trip', () {
    test('saved spaces are returned by load with id and name intact', () async {
      const key = 'user1@https://example.com';
      final spaces = [_space('s1', 'General'), _space('s2', 'Gaming')];

      await SpaceCache.save(key, spaces);
      final loaded = SpaceCache.load(key);

      expect(loaded, hasLength(2));
      expect(loaded[0].id, 's1');
      expect(loaded[0].name, 'General');
      expect(loaded[1].id, 's2');
      expect(loaded[1].name, 'Gaming');
    });

    test('saving an empty list is retrievable as an empty list', () async {
      const key = 'user1@https://example.com';
      await SpaceCache.save(key, []);
      expect(SpaceCache.load(key), isEmpty);
    });

    test('load returns empty list for an unknown key', () {
      expect(SpaceCache.load('no-such-key'), isEmpty);
    });

    test('saving twice overwrites the previous value', () async {
      const key = 'user1@https://example.com';
      await SpaceCache.save(key, [_space('old', 'Old')]);
      await SpaceCache.save(key, [_space('new', 'New')]);
      final loaded = SpaceCache.load(key);
      expect(loaded, hasLength(1));
      expect(loaded[0].id, 'new');
    });

    test('two independent keys do not interfere', () async {
      await SpaceCache.save('key-a', [_space('a', 'Alpha')]);
      await SpaceCache.save('key-b', [_space('b', 'Beta')]);
      expect(SpaceCache.load('key-a')[0].id, 'a');
      expect(SpaceCache.load('key-b')[0].id, 'b');
    });
  });

  group('SpaceCache.remove', () {
    test('removes the entry for the given key', () async {
      const key = 'user1@https://example.com';
      await SpaceCache.save(key, [_space('s1', 'Lobby')]);
      await SpaceCache.remove(key);
      expect(SpaceCache.load(key), isEmpty);
    });

    test('removing an absent key is a no-op (no throw)', () async {
      await expectLater(SpaceCache.remove('ghost-key'), completes);
    });
  });

  group('SpaceCache.clear', () {
    test('wipes all entries', () async {
      await SpaceCache.save('key-a', [_space('a', 'A')]);
      await SpaceCache.save('key-b', [_space('b', 'B')]);
      await SpaceCache.clear();
      expect(SpaceCache.load('key-a'), isEmpty);
      expect(SpaceCache.load('key-b'), isEmpty);
    });

    test('clear on an already-empty cache is a no-op', () async {
      await expectLater(SpaceCache.clear(), completes);
    });
  });

  group('SpaceCache.load resilience', () {
    test('returns empty list when the stored value is not a JSON string', () {
      Hive.box<dynamic>(SpaceCache.boxName).put('bad-key', 42);
      expect(SpaceCache.load('bad-key'), isEmpty);
    });

    test('returns empty list when the stored value is not a JSON list', () {
      Hive.box<dynamic>(SpaceCache.boxName).put('bad-key', '{"not":"a list"}');
      expect(SpaceCache.load('bad-key'), isEmpty);
    });

    test('skips non-map entries inside the JSON list without throwing', () {
      Hive.box<dynamic>(SpaceCache.boxName)
          .put('partial-key', '[null, 42, {"id":"ok","name":"OK"}]');
      final loaded = SpaceCache.load('partial-key');
      expect(loaded, hasLength(1));
      expect(loaded[0].id, 'ok');
    });
  });
}
