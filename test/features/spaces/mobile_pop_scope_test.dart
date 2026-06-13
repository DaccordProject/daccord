import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal widget that replicates the PopScope + Scaffold + drawer structure
/// used in AccordHomeScreen's narrow layout, stripped of all network/Riverpod
/// dependencies so the back-gesture drawer logic can be exercised in isolation.
class _MobileHome extends StatefulWidget {
  const _MobileHome({this.hasEndDrawer = true});

  final bool hasEndDrawer;

  @override
  State<_MobileHome> createState() => _MobileHomeState();
}

class _MobileHomeState extends State<_MobileHome> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) return;
      final scaffold = _scaffoldKey.currentState;
      if (scaffold == null) return;
      if (scaffold.isEndDrawerOpen) {
        scaffold.closeEndDrawer();
      } else if (scaffold.isDrawerOpen) {
        scaffold.closeDrawer();
      } else {
        scaffold.openDrawer();
      }
    },
    child: Scaffold(
      key: _scaffoldKey,
      drawer: const Drawer(child: Text('channels')),
      endDrawer: widget.hasEndDrawer
          ? const Drawer(child: Text('members'))
          : null,
      body: const Center(child: Text('content')),
    ),
  );
}

void main() {
  group('mobile narrow-layout PopScope back-gesture behavior', () {
    testWidgets('opens channel drawer when no drawer is open', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _MobileHome()));
      final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold));

      expect(scaffold.isDrawerOpen, isFalse);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(scaffold.isDrawerOpen, isTrue);
    });

    testWidgets('closes channel drawer when it is open', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _MobileHome()));
      final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold));

      scaffold.openDrawer();
      await tester.pumpAndSettle();
      expect(scaffold.isDrawerOpen, isTrue);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(scaffold.isDrawerOpen, isFalse);
    });

    testWidgets('closes end drawer (members) when it is open', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _MobileHome()));
      final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold));

      scaffold.openEndDrawer();
      await tester.pumpAndSettle();
      expect(scaffold.isEndDrawerOpen, isTrue);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(scaffold.isEndDrawerOpen, isFalse);
    });

    testWidgets('does not pop the route when no drawer is open', (tester) async {
      // Regression guard: back must never pop /spaces back to the sign-in screen.
      // Push a route before _MobileHome so there is somewhere to pop to.
      await tester.pumpWidget(
        MaterialApp(
          initialRoute: '/home',
          routes: {
            '/': (_) => const Scaffold(body: Text('sign-in')),
            '/home': (_) => const _MobileHome(),
          },
        ),
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Sign-in screen must not be shown.
      expect(find.text('sign-in'), findsNothing);
      expect(find.text('content'), findsOneWidget);
    });

    testWidgets('works without an end drawer (no space selected)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: _MobileHome(hasEndDrawer: false)),
      );
      final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold));

      expect(scaffold.isDrawerOpen, isFalse);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(scaffold.isDrawerOpen, isTrue);
    });
  });
}
