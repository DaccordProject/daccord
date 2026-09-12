import 'package:bonfire/features/spaces/views/rail_draggable.dart';
import 'package:bonfire/shared/components/context_menu.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _theme = BonfireThemeExtension(
  foreground: Colors.white,
  background: Color(0xFF1e1f22),
  dirtyWhite: Color(0xFFdcddde),
  gray: Color(0xFF949ba4),
  darkGray: Color(0xFF4e5058),
  primary: Color(0xFF5865f2),
  red: Color(0xFFed4245),
  green: Color(0xFF23a55a),
  yellow: Color(0xFFf0b232),
);

/// Replicates the space rail's gesture stack (#327): a scrollable column of
/// [RailDraggable] tiles whose child — like `_SpaceIcon` — has its own tap
/// detector, and whose menu is the real [showAccordContextMenu]. Stripped of
/// Riverpod/network so the gesture arena can be exercised alone.
class _Rail extends StatefulWidget {
  const _Rail({required this.log});

  final List<String> log;

  @override
  State<_Rail> createState() => _RailState();
}

class _RailState extends State<_Rail> {
  final _scroll = ScrollController();
  String? _dropped;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Widget _tile(BuildContext context, String name) => RailDraggable<String>(
    key: ValueKey('tile-$name'),
    data: name,
    tooltip: name,
    feedback: SizedBox(
      key: ValueKey('feedback-$name'),
      width: 48,
      height: 48,
      child: const ColoredBox(color: Colors.blue),
    ),
    childWhenDragging: const SizedBox(width: 48, height: 48),
    onMenu: (position) {
      widget.log.add('menu:$name:${position == null ? 'sheet' : 'anchored'}');
      showAccordContextMenu(
        context,
        entries: [
          AccordMenuEntry(
            label: 'Mute server',
            icon: Icons.notifications_off_outlined,
            onSelected: () => widget.log.add('mute:$name'),
          ),
        ],
        globalPosition: position,
      );
    },
    child: GestureDetector(
      onTap: () => widget.log.add('tap:$name'),
      child: SizedBox(
        width: 48,
        height: 48,
        child: ColoredBox(color: Colors.grey, child: Text('icon-$name')),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 72,
        child: ListView(
          controller: _scroll,
          children: [
            for (var i = 0; i < 30; i++)
              Padding(
                padding: const EdgeInsets.all(6),
                child: Center(
                  child: Builder(builder: (ctx) => _tile(ctx, 'space$i')),
                ),
              ),
          ],
        ),
      ),
      Expanded(
        child: DragTarget<String>(
          onAcceptWithDetails: (d) => setState(() => _dropped = d.data),
          builder: (_, _, _) => Center(
            child: Text(_dropped == null ? 'drop here' : 'dropped:$_dropped'),
          ),
        ),
      ),
    ],
  );
}

Widget _app(List<String> log) => MaterialApp(
  theme: ThemeData(extensions: const [_theme]),
  home: Scaffold(body: _Rail(log: log)),
);

Finder _tile(String name) => find.byKey(ValueKey('tile-$name'));
Finder _feedback(String name) => find.byKey(ValueKey('feedback-$name'));

/// A hold long enough for [LongPressDraggable] to lift the tile.
const _hold = Duration(milliseconds: 600);

void main() {
  const touch = TargetPlatformVariant({
    TargetPlatform.android,
    TargetPlatform.iOS,
  });
  const desktop = TargetPlatformVariant({TargetPlatform.linux});

  group('RailDraggable on touch', () {
    testWidgets('a long-press released in place opens the menu as a sheet', (
      tester,
    ) async {
      final log = <String>[];
      await tester.pumpWidget(_app(log));

      await tester.longPress(_tile('space1'), kind: PointerDeviceKind.touch);
      await tester.pumpAndSettle();

      expect(log, ['menu:space1:sheet']);
      expect(find.text('Mute server'), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
      // The regression: the name tooltip must not have claimed the press.
      expect(find.text('space1'), findsNothing);
      expect(_feedback('space1'), findsNothing);

      await tester.tap(find.text('Mute server'));
      await tester.pumpAndSettle();
      expect(log, ['menu:space1:sheet', 'mute:space1']);
      expect(find.byType(BottomSheet), findsNothing);
    }, variant: touch);

    testWidgets('a plain tap selects the space without a menu', (tester) async {
      final log = <String>[];
      await tester.pumpWidget(_app(log));

      await tester.tap(_tile('space2'), kind: PointerDeviceKind.touch);
      await tester.pumpAndSettle();

      expect(log, ['tap:space2']);
      expect(find.text('Mute server'), findsNothing);
      expect(_feedback('space2'), findsNothing);
    }, variant: touch);

    testWidgets('a long-press then drag lifts the tile, and a drop opens '
        'no menu', (tester) async {
      final log = <String>[];
      await tester.pumpWidget(_app(log));

      final gesture = await tester.startGesture(
        tester.getCenter(_tile('space3')),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(_hold);
      expect(_feedback('space3'), findsOneWidget, reason: 'lifted');
      expect(find.text('Mute server'), findsNothing);

      await gesture.moveBy(const Offset(300, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('dropped:space3'), findsOneWidget);
      expect(log, isEmpty);
      expect(find.text('Mute server'), findsNothing);
    }, variant: touch);

    testWidgets('a drag that misses every target opens no menu either', (
      tester,
    ) async {
      final log = <String>[];
      await tester.pumpWidget(_app(log));

      final gesture = await tester.startGesture(
        tester.getCenter(_tile('space3')),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(_hold);
      // Down the rail, still over the list (no drop target) — a reorder
      // attempt that fell through, not a request for actions.
      await gesture.moveBy(const Offset(0, 120));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(log, isEmpty);
      expect(find.text('Mute server'), findsNothing);
    }, variant: touch);

    testWidgets('a quick finger-scroll still scrolls the rail', (tester) async {
      final log = <String>[];
      await tester.pumpWidget(_app(log));
      final scrollable = find.byType(Scrollable).first;
      final state = tester.state<ScrollableState>(scrollable);
      expect(state.position.pixels, 0);

      await tester.drag(
        _tile('space4'),
        const Offset(0, -200),
        kind: PointerDeviceKind.touch,
      );
      await tester.pumpAndSettle();

      expect(state.position.pixels, greaterThan(0));
      expect(log, isEmpty);
      expect(find.text('Mute server'), findsNothing);
      expect(_feedback('space4'), findsNothing);
    }, variant: touch);
  });

  group('RailDraggable on desktop', () {
    testWidgets('right-click opens the menu anchored at the pointer', (
      tester,
    ) async {
      final log = <String>[];
      await tester.pumpWidget(_app(log));

      await tester.tap(
        _tile('space1'),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();

      expect(log, ['menu:space1:anchored']);
      expect(find.text('Mute server'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
    }, variant: desktop);

    testWidgets('a click-drag starts immediately', (tester) async {
      final log = <String>[];
      await tester.pumpWidget(_app(log));

      final gesture = await tester.startGesture(
        tester.getCenter(_tile('space2')),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(300, 0));
      await tester.pump();
      expect(_feedback('space2'), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('dropped:space2'), findsOneWidget);
      expect(log, isEmpty);
    }, variant: desktop);

    testWidgets('hovering shows the name tooltip', (tester) async {
      final log = <String>[];
      await tester.pumpWidget(_app(log));

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(_tile('space1')));
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('space1'), findsOneWidget);
    }, variant: desktop);
  });
}
