import 'package:bonfire/features/server/services/federation_join.dart';
import 'package:bonfire/features/server/utils/server_uri.dart';
import 'package:bonfire/features/server/views/federation_join_confirmation.dart';
import 'package:bonfire/theme/theme.dart';
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

Widget _confirmationHost({required FederatedJoinAction join}) {
  return MaterialApp(
    theme: ThemeData(extensions: const [_theme]),
    home: Builder(
      builder: (context) => Scaffold(
        body: ElevatedButton(
          onPressed: () => confirmFederatedDeepLinkJoin(
            context,
            activeAccount: 'Alice (user-1) on home.example',
            domain: 'remote.example',
            spaceId: 'space-42',
            join: join,
          ),
          child: const Text('Open link'),
        ),
      ),
    ),
  );
}

void main() {
  group('parseFederatedAddress', () {
    test('splits spaceId@domain', () {
      final addr = parseFederatedAddress('42@b.example');
      expect(addr?.spaceId, '42');
      expect(addr?.domain, 'b.example');
    });

    test('trims whitespace', () {
      final addr = parseFederatedAddress('  42@b.example  ');
      expect(addr?.spaceId, '42');
      expect(addr?.domain, 'b.example');
    });

    test('rejects input without a domain', () {
      expect(parseFederatedAddress('42'), isNull);
      expect(parseFederatedAddress('42@'), isNull);
      expect(parseFederatedAddress('@b.example'), isNull);
    });

    test('uses last @ so a qualified spaceId is preserved', () {
      // A space ID that is already qualified (e.g. from another federated hop)
      // still splits correctly: everything before the final @ is the space id.
      final addr = parseFederatedAddress('42@olddomain.example@newdomain.example');
      expect(addr?.spaceId, '42@olddomain.example');
      expect(addr?.domain, 'newdomain.example');
    });
  });

  group('federate deep link', () {
    test('parses daccord://federate/<spaceId>@<domain>', () {
      final parsed = ServerUri.parseDeepLink('daccord://federate/42@b.example');
      expect(parsed?.route, 'federate');
      expect(parsed?.spaceId, '42');
      expect(parsed?.domain, 'b.example');
    });

    test('rejects a federate link without a domain', () {
      expect(ServerUri.parseDeepLink('daccord://federate/42'), isNull);
    });

    test('preserves qualified spaceId in federate deep link', () {
      final parsed = ServerUri.parseDeepLink(
          'daccord://federate/42@olddomain.example@newdomain.example');
      expect(parsed?.route, 'federate');
      expect(parsed?.spaceId, '42@olddomain.example');
      expect(parsed?.domain, 'newdomain.example');
    });
  });

  group('federate deep-link confirmation', () {
    testWidgets('cancel performs no join mutation', (tester) async {
      var joinCalls = 0;
      await tester.pumpWidget(
        _confirmationHost(
          join: () async {
            joinCalls++;
            return (spaceId: 'space-42@remote.example', error: null);
          },
        ),
      );

      await tester.tap(find.text('Open link'));
      await tester.pumpAndSettle();

      expect(find.text('Join federated space?'), findsOneWidget);
      expect(
        find.textContaining('Active account: Alice (user-1) on home.example'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Destination domain: remote.example'),
        findsOneWidget,
      );
      expect(find.textContaining('Space: space-42'), findsOneWidget);
      expect(joinCalls, 0);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(joinCalls, 0);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('confirm performs the join mutation once', (tester) async {
      var joinCalls = 0;
      await tester.pumpWidget(
        _confirmationHost(
          join: () async {
            joinCalls++;
            return (spaceId: 'space-42@remote.example', error: null);
          },
        ),
      );

      await tester.tap(find.text('Open link'));
      await tester.pumpAndSettle();
      expect(joinCalls, 0);

      await tester.tap(find.text('Join space'));
      await tester.pumpAndSettle();

      expect(joinCalls, 1);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
