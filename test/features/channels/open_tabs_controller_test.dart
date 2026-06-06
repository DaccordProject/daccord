import 'dart:io';

import 'package:bonfire/features/channels/controllers/open_tabs.dart';
import 'package:bonfire/features/channels/models/open_tab.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('open-tabs-test');
    Hive.init(tempDir.path);
    await Hive.openBox('accord-settings');
  });

  tearDown(() async {
    await Hive.deleteBoxFromDisk('accord-settings');
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  OpenTabsController controllerOf(ProviderContainer c) =>
      c.read(openTabsControllerProvider.notifier);

  OpenTabsState stateOf(ProviderContainer c) =>
      c.read(openTabsControllerProvider);

  OpenTab tab(String channelId, {String space = 's1', String server = 'k1'}) =>
      OpenTab(
        channelId: channelId,
        spaceId: space,
        serverKey: server,
        name: '#$channelId',
      );

  group('open', () {
    test('adds a tab and makes it active', () {
      final c = makeContainer();
      controllerOf(c).open(tab('a'));
      expect(stateOf(c).tabs.map((t) => t.channelId), ['a']);
      expect(stateOf(c).activeTab?.channelId, 'a');
    });

    test('re-opening an existing tab switches to it without duplicating', () {
      final c = makeContainer();
      controllerOf(c)
        ..open(tab('a'))
        ..open(tab('b'))
        ..open(tab('a'));
      expect(stateOf(c).tabs.map((t) => t.channelId), ['a', 'b']);
      expect(stateOf(c).activeTab?.channelId, 'a');
    });
  });

  group('close', () {
    test('closing the active tab activates the neighbour in its slot', () {
      final c = makeContainer();
      controllerOf(c)
        ..open(tab('a'))
        ..open(tab('b'))
        ..open(tab('c'))
        ..activate(tab('b').key)
        ..close(tab('b').key);
      expect(stateOf(c).tabs.map((t) => t.channelId), ['a', 'c']);
      // 'c' slid into b's index, so it becomes active.
      expect(stateOf(c).activeTab?.channelId, 'c');
    });

    test('closeOthers keeps only the target', () {
      final c = makeContainer();
      controllerOf(c)
        ..open(tab('a'))
        ..open(tab('b'))
        ..open(tab('c'))
        ..closeOthers(tab('a').key);
      expect(stateOf(c).tabs.map((t) => t.channelId), ['a']);
      expect(stateOf(c).activeTab?.channelId, 'a');
    });

    test('closeToRight drops everything after the target', () {
      final c = makeContainer();
      controllerOf(c)
        ..open(tab('a'))
        ..open(tab('b'))
        ..open(tab('c'))
        ..closeToRight(tab('a').key);
      expect(stateOf(c).tabs.map((t) => t.channelId), ['a']);
      expect(stateOf(c).activeTab?.channelId, 'a');
    });
  });

  group('reorder', () {
    test('moving a tab to the end reorders the list', () {
      final c = makeContainer();
      controllerOf(c)
        ..open(tab('a'))
        ..open(tab('b'))
        ..open(tab('c'))
        ..reorder(0, 3); // Flutter passes newIndex past the end.
      expect(stateOf(c).tabs.map((t) => t.channelId), ['b', 'c', 'a']);
    });
  });

  group('removeForServer', () {
    test('drops only that server\'s tabs and fixes the active selection', () {
      final c = makeContainer();
      controllerOf(c)
        ..open(tab('a', server: 'k1'))
        ..open(tab('b', server: 'k2'))
        ..activate(tab('a', server: 'k1').key)
        ..removeForServer('k1');
      expect(stateOf(c).tabs.map((t) => t.channelId), ['b']);
      expect(stateOf(c).activeTab, isNull);
    });
  });

  group('persistence', () {
    test('open tabs survive a controller rebuild (re-reading the box)', () {
      final c = makeContainer();
      controllerOf(c)
        ..open(tab('a'))
        ..open(tab('b'));
      // A fresh container reads the persisted box on build.
      final c2 = makeContainer();
      expect(stateOf(c2).tabs.map((t) => t.channelId), ['a', 'b']);
      expect(stateOf(c2).activeTab?.channelId, 'b');
    });
  });
}
