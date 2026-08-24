import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/channels/controllers/dm_channels.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/user/views/accord_direct_messages.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [DmChannelsController] exposing a fixed conversation list, so the DM
/// dialog renders without a server.
class _FakeDmChannels extends DmChannelsController {
  _FakeDmChannels(this._channels);

  final List<AccordChannel> _channels;

  @override
  List<AccordChannel>? build(String serverKey) => _channels;
}

class _FakeSettingsController extends SettingsController {
  @override
  AccordSettings build() => const AccordSettings();
}

AccordChannel _dm(String id, String withName) => AccordChannel(
  id: id,
  type: 'dm',
  recipients: [AccordUser(id: 'u-$id', username: withName)],
);

void main() {
  late ProviderContainer container;

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(AppThemePreset.dark),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAccordDirectMessages(context),
                child: const Text('open dms'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open dms'));
    await tester.pumpAndSettle();
  }

  setUp(() {
    container = ProviderContainer(
      overrides: [
        settingsControllerProvider.overrideWith(_FakeSettingsController.new),
        dmChannelsControllerProvider('').overrideWith(
          () => _FakeDmChannels([_dm('dm1', 'bob'), _dm('dm2', 'carol')]),
        ),
      ],
    );
  });

  tearDown(() => container.dispose());

  testWidgets('search narrows the conversation list by title', (tester) async {
    await openDialog(tester);
    expect(find.text('bob'), findsOneWidget);
    expect(find.text('carol'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'car');
    await tester.pump();

    expect(find.text('bob'), findsNothing);
    expect(find.text('carol'), findsOneWidget);
  });

  testWidgets('search is case-insensitive and trims whitespace', (
    tester,
  ) async {
    await openDialog(tester);

    await tester.enterText(find.byType(TextField), '  BOB  ');
    await tester.pump();

    expect(find.text('bob'), findsOneWidget);
    expect(find.text('carol'), findsNothing);
  });

  testWidgets('a query matching nothing shows the empty-results message', (
    tester,
  ) async {
    await openDialog(tester);

    await tester.enterText(find.byType(TextField), 'nobody-has-this-name');
    await tester.pump();

    expect(find.text('bob'), findsNothing);
    expect(find.text('carol'), findsNothing);
    expect(find.text('No matching conversations'), findsOneWidget);
    expect(find.text('No direct messages yet'), findsNothing);
  });

  testWidgets('clearing the query restores the full list', (tester) async {
    await openDialog(tester);

    await tester.enterText(find.byType(TextField), 'car');
    await tester.pump();
    expect(find.text('bob'), findsNothing);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();

    expect(find.text('bob'), findsOneWidget);
    expect(find.text('carol'), findsOneWidget);
  });
}
