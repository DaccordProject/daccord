import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/channels/controllers/dm_channels.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/user/views/accord_direct_messages.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reaching Report and Block from a direct message (App Review 1.2, #290).
///
/// A DM has no space, so the space-scoped member popout can't open there: a tap
/// on a DM user lands on the account-level profile, and the conversation's
/// report/block menu used to open on long-press or right-click only. Both were
/// dead ends for a reviewer tapping around. These hold the two affordances in
/// place.

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

final _them = AccordUser(id: 'u2', username: 'bob');

AccordChannel get _dm =>
    AccordChannel(id: 'dm1', type: 'dm', recipients: [_them]);

/// There is no client in this harness, so the message pane stays in its
/// loading state — pump explicit frames rather than waiting for it to settle.
Future<void> _tick(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        settingsControllerProvider.overrideWith(_FakeSettingsController.new),
        dmChannelsControllerProvider(
          '',
        ).overrideWith(() => _FakeDmChannels([_dm])),
      ],
    );
  });

  tearDown(() => container.dispose());

  Widget app(VoidCallback Function(BuildContext context) onPressed) =>
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(AppThemePreset.dark),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: onPressed(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

  testWidgets('a DM user profile can report and block that account', (
    tester,
  ) async {
    await tester.pumpWidget(
      app((context) => () => showAccordUserProfile(context, _them)),
    );
    await tester.tap(find.text('open'));
    await _tick(tester);

    expect(find.text('Report user'), findsOneWidget);
    expect(find.text('Block'), findsOneWidget);

    await tester.tap(find.text('Report user'));
    await _tick(tester);

    expect(find.text('Report bob'), findsOneWidget);
    expect(find.text('Submit report'), findsOneWidget);
  });

  testWidgets('blocking from a DM user profile asks for confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(
      app((context) => () => showAccordUserProfile(context, _them)),
    );
    await tester.tap(find.text('open'));
    await _tick(tester);

    await tester.tap(find.text('Block'));
    await _tick(tester);

    expect(find.text('Block user'), findsOneWidget);
    expect(
      find.textContaining('Blocked users cannot DM you'),
      findsOneWidget,
    );
  });

  testWidgets('the 1:1 DM header has a visible menu carrying Report and Block', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        (context) => () => showAccordDirectMessages(
          context,
          initialChannel: _dm,
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await _tick(tester);

    // The group menu is group-only; a 1:1 gets its own overflow button.
    expect(find.byTooltip('Group options'), findsNothing);
    expect(find.byTooltip('Conversation options'), findsOneWidget);

    await tester.tap(find.byTooltip('Conversation options'));
    await _tick(tester);

    expect(find.text('Report user'), findsOneWidget);
    expect(find.text('Block'), findsOneWidget);

    await tester.tap(find.text('Report user'));
    await _tick(tester);

    expect(find.text('Report bob'), findsOneWidget);
  });
}
