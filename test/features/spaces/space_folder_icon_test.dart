import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/spaces/models/space_folder.dart';
import 'package:bonfire/features/spaces/views/accord_home.dart';
import 'package:bonfire/features/spaces/views/rail_draggable.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  theme: buildAppTheme(AppThemePreset.dark),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  final spaces = <String, AccordSpace>{
    for (var i = 0; i < 6; i++)
      'space-$i': AccordSpace(id: '$i', name: String.fromCharCode(65 + i)),
  };

  for (final dpr in [1.0, 2.0]) {
    for (final count in [0, 1, 3, 4, 6]) {
      testWidgets('$count members fill at most four ordered slots at ${dpr}x', (
        tester,
      ) async {
        tester.view.devicePixelRatio = dpr;
        addTearDown(tester.view.resetDevicePixelRatio);
        // Reverse the folder order to ensure cache iteration order isn't used.
        final ids = spaces.keys.take(count).toList().reversed.toList();
        final folder = SpaceFolder(
          id: 'folder',
          collapsed: true,
          spaceIds: ids,
        );
        await tester.pumpWidget(
          _host(SpaceFolderIcon(folder: folder, spaces: spaces)),
        );
        expect(
          tester.getSize(find.byType(SpaceFolderIcon)),
          const Size(48, 48),
        );
        final expected = ids.take(4).map((id) => spaces[id]!.name).toList();
        expect(
          find.byIcon(Icons.folder),
          count == 0 ? findsOneWidget : findsNothing,
        );
        expect(find.byType(ClipRRect), findsNWidgets(expected.length));
        for (var i = 0; i < expected.length; i++) {
          final label = find.text(expected[i]);
          expect(label, findsOneWidget);
          final tile = find.ancestor(
            of: label,
            matching: find.byType(ClipRRect),
          );
          expect(tester.getSize(tile), const Size(18, 18));
          final origin = tester.getTopLeft(find.byType(SpaceFolderIcon));
          expect(
            tester.getTopLeft(tile) - origin,
            Offset(5.0 + (i % 2) * 20, 5.0 + (i ~/ 2) * 20),
          );
        }
        for (final name
            in spaces.values
                .map((space) => space.name)
                .where((name) => !expected.contains(name))) {
          expect(find.text(name), findsNothing);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'missing spaces are skipped before selecting four and cache fills refresh the preview',
    (tester) async {
      const folder = SpaceFolder(
        id: 'folder',
        collapsed: true,
        spaceIds: [
          'missing',
          'space-3',
          'space-1',
          'missing-again',
          'space-4',
          'space-0',
          'space-2',
        ],
      );
      await tester.pumpWidget(
        _host(SpaceFolderIcon(folder: folder, spaces: spaces)),
      );
      expect(
        tester.widgetList<Text>(find.byType(Text)).map((text) => text.data),
        ['D', 'B', 'E', 'A'],
      );
      await tester.pumpWidget(
        _host(
          SpaceFolderIcon(
            folder: folder,
            spaces: {
              ...spaces,
              'missing': AccordSpace(id: 'loaded', name: 'New Space'),
            },
          ),
        ),
      );
      expect(
        tester.widgetList<Text>(find.byType(Text)).map((text) => text.data),
        ['NS', 'D', 'B', 'E'],
      );
    },
  );

  testWidgets(
    'all missing members and expanded folders retain the tinted glyph',
    (tester) async {
      const folder = SpaceFolder(
        id: 'folder',
        color: 0xFFFF0000,
        collapsed: true,
        spaceIds: ['missing'],
      );
      await tester.pumpWidget(
        _host(SpaceFolderIcon(folder: folder, spaces: spaces)),
      );
      expect(find.byIcon(Icons.folder), findsOneWidget);
      final tile = tester.widget<Container>(find.byType(Container).first);
      expect(
        (tile.decoration! as BoxDecoration).color,
        const Color(0xFFFF0000).withValues(alpha: 0.5),
      );
      await tester.pumpWidget(
        _host(
          SpaceFolderIcon(
            folder: folder.copyWith(
              collapsed: false,
              spaceIds: spaces.keys.toList(),
            ),
            spaces: spaces,
          ),
        ),
      );
      expect(find.byIcon(Icons.folder_open), findsOneWidget);
      expect(find.byType(ClipRRect), findsNothing);
    },
  );

  testWidgets(
    'qualified membership keeps colliding IDs distinct and shares initials fallback',
    (tester) async {
      const folder = SpaceFolder(
        id: 'folder',
        collapsed: true,
        spaceIds: ['server-b/same', 'server-a/same', 'blank'],
      );
      await tester.pumpWidget(
        _host(
          SpaceFolderIcon(
            folder: folder,
            spaces: {
              'server-a/same': AccordSpace(id: 'same', name: 'Alpha Team'),
              'server-b/same': AccordSpace(id: 'same', name: 'Beta Team'),
              'blank': AccordSpace(id: 'blank', name: '  '),
            },
          ),
        ),
      );
      expect(
        tester.widgetList<Text>(find.byType(Text)).map((text) => text.data),
        ['BT', 'AT', '?'],
      );
    },
  );

  testWidgets(
    'folder preview survives both drag feedback and the faded source',
    (tester) async {
      final icon = SpaceFolderIcon(
        folder: const SpaceFolder(
          id: 'folder',
          name: 'My folder',
          collapsed: true,
          spaceIds: ['space-0', 'space-1', 'space-2'],
        ),
        spaces: spaces,
      );
      await tester.pumpWidget(
        _host(
          RailDraggable<String>(
            data: 'folder',
            tooltip: 'My folder',
            feedback: Material(color: Colors.transparent, child: icon),
            childWhenDragging: Opacity(opacity: 0.3, child: icon),
            child: icon,
          ),
        ),
      );
      expect(find.byTooltip('My folder'), findsOneWidget);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(SpaceFolderIcon)),
      );
      await gesture.moveBy(const Offset(100, 40));
      await tester.pump();
      expect(find.byType(SpaceFolderIcon), findsNWidgets(2));
      for (final label in ['A', 'B', 'C']) {
        expect(find.text(label), findsNWidgets(2));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byType(SpaceFolderIcon), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
