import 'package:bonfire/shared/components/drawer_swipe_area.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Replicates the narrow-layout body of `AccordHomeScreen`: a horizontally
/// scrollable tab strip above a message area, all inside a [DrawerSwipeArea].
/// Stripped of Riverpod/network so the gesture wiring can be exercised alone.
class _MobileHome extends StatelessWidget {
  const _MobileHome({
    required this.scaffoldKey,
    required this.tabScroll,
    this.hasEndDrawer = true,
    this.textDirection = TextDirection.ltr,
  });

  final GlobalKey<ScaffoldState> scaffoldKey;
  final ScrollController tabScroll;
  final bool hasEndDrawer;
  final TextDirection textDirection;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: textDirection,
    child: Scaffold(
      key: scaffoldKey,
      drawerEdgeDragWidth: 48,
      drawer: const Drawer(child: Text('channels')),
      endDrawer: hasEndDrawer ? const Drawer(child: Text('members')) : null,
      body: DrawerSwipeArea(
        scaffoldKey: scaffoldKey,
        child: Column(
          children: [
            SizedBox(
              height: 38,
              child: ListView(
                controller: tabScroll,
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < 30; i++)
                    SizedBox(width: 80, child: Text('tab$i')),
                ],
              ),
            ),
            const Expanded(child: ColoredBox(color: Colors.black)),
          ],
        ),
      ),
    ),
  );
}

/// Somewhere in the message area, well clear of both edge drag strips.
const Offset _midBody = Offset(400, 400);

/// On the tab strip (38 logical pixels tall), clear of the edge strips.
const Offset _onTabStrip = Offset(400, 19);

void main() {
  group('drawerSwipeAction', () {
    test('ignores a drag that never commits to a direction', () {
      expect(
        drawerSwipeAction(distance: 12, velocity: 40),
        DrawerSwipeAction.none,
      );
    });

    test('opens the drawer once the drag passes the distance threshold', () {
      expect(
        drawerSwipeAction(distance: kDrawerSwipeDistance, velocity: 0),
        DrawerSwipeAction.openDrawer,
      );
    });

    test('opens the end drawer on the mirrored distance', () {
      expect(
        drawerSwipeAction(distance: -kDrawerSwipeDistance, velocity: 0),
        DrawerSwipeAction.openEndDrawer,
      );
    });

    test('a short flick still opens on velocity alone', () {
      expect(
        drawerSwipeAction(distance: 5, velocity: kDrawerSwipeVelocity),
        DrawerSwipeAction.openDrawer,
      );
      expect(
        drawerSwipeAction(distance: -5, velocity: -kDrawerSwipeVelocity),
        DrawerSwipeAction.openEndDrawer,
      );
    });

    test('a decisive flick outvotes distance dragged the other way', () {
      expect(
        drawerSwipeAction(distance: 200, velocity: -900),
        DrawerSwipeAction.openEndDrawer,
      );
    });
  });

  group('DrawerSwipeArea', () {
    late GlobalKey<ScaffoldState> key;
    late ScrollController tabScroll;

    setUp(() {
      key = GlobalKey<ScaffoldState>();
      tabScroll = ScrollController();
    });

    tearDown(() => tabScroll.dispose());

    Future<void> pumpHome(
      WidgetTester tester, {
      bool hasEndDrawer = true,
      TargetPlatform platform = TargetPlatform.android,
      TextDirection textDirection = TextDirection.ltr,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: _MobileHome(
            scaffoldKey: key,
            tabScroll: tabScroll,
            hasEndDrawer: hasEndDrawer,
            textDirection: textDirection,
          ),
        ),
      );
    }

    testWidgets('a swipe from mid-body opens the channel drawer', (
      tester,
    ) async {
      await pumpHome(tester);
      expect(key.currentState!.isDrawerOpen, isFalse);

      await tester.dragFrom(_midBody, const Offset(250, 0));
      await tester.pumpAndSettle();

      expect(key.currentState!.isDrawerOpen, isTrue);
    });

    testWidgets('the edge strip still opens the drawer', (tester) async {
      await pumpHome(tester);

      await tester.dragFrom(const Offset(10, 400), const Offset(250, 0));
      await tester.pumpAndSettle();

      expect(key.currentState!.isDrawerOpen, isTrue);
    });

    testWidgets('a swipe back from mid-body opens the member drawer', (
      tester,
    ) async {
      await pumpHome(tester);

      await tester.dragFrom(_midBody, const Offset(-250, 0));
      await tester.pumpAndSettle();

      expect(key.currentState!.isEndDrawerOpen, isTrue);
    });

    testWidgets('a swipe back does nothing when there is no member drawer', (
      tester,
    ) async {
      await pumpHome(tester, hasEndDrawer: false);

      await tester.dragFrom(_midBody, const Offset(-250, 0));
      await tester.pumpAndSettle();

      expect(key.currentState!.isDrawerOpen, isFalse);
      expect(key.currentState!.isEndDrawerOpen, isFalse);
    });

    testWidgets('a twitch below the threshold opens nothing', (tester) async {
      await pumpHome(tester);

      await tester.dragFrom(_midBody, const Offset(24, 0));
      await tester.pumpAndSettle();

      expect(key.currentState!.isDrawerOpen, isFalse);
    });

    testWidgets('a vertical drag opens nothing', (tester) async {
      await pumpHome(tester);

      await tester.dragFrom(_midBody, const Offset(0, -250));
      await tester.pumpAndSettle();

      expect(key.currentState!.isDrawerOpen, isFalse);
      expect(key.currentState!.isEndDrawerOpen, isFalse);
    });

    testWidgets('the tab strip keeps its own horizontal drag', (tester) async {
      await pumpHome(tester);
      tabScroll.jumpTo(400);
      await tester.pump();

      await tester.dragFrom(_onTabStrip, const Offset(150, 0));
      await tester.pumpAndSettle();

      expect(tabScroll.offset, lessThan(400));
      expect(key.currentState!.isDrawerOpen, isFalse);
    });

    testWidgets('desktop platforms keep the pointer-driven behavior', (
      tester,
    ) async {
      await pumpHome(tester, platform: TargetPlatform.linux);

      await tester.dragFrom(_midBody, const Offset(250, 0));
      await tester.pumpAndSettle();

      expect(key.currentState!.isDrawerOpen, isFalse);
    });

    testWidgets('right-to-left mirrors which edge each swipe opens', (
      tester,
    ) async {
      await pumpHome(tester, textDirection: TextDirection.rtl);

      // In RTL the channel drawer hangs off the right, so it is the leftward
      // swipe that pulls it in.
      await tester.dragFrom(_midBody, const Offset(-250, 0));
      await tester.pumpAndSettle();

      expect(key.currentState!.isDrawerOpen, isTrue);
    });
  });
}
