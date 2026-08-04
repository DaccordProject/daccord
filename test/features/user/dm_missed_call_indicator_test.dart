import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/channels/controllers/dm_channels.dart';
import 'package:bonfire/features/user/views/accord_direct_messages.dart';
import 'package:bonfire/features/voice/controllers/missed_calls.dart';
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
  List<AccordChannel>? build() => _channels;
}

AccordChannel _dm(String id, String withName) => AccordChannel(
      id: id,
      type: 'dm',
      recipients: [AccordUser(id: 'u2', username: withName)],
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
        dmChannelsControllerProvider
            .overrideWith(() => _FakeDmChannels([_dm('dm1', 'bob')])),
      ],
    );
  });

  tearDown(() => container.dispose());

  testWidgets('no missed call means no indicator', (tester) async {
    await openDialog(tester);
    expect(find.text('bob'), findsOneWidget);
    expect(find.text('Missed call'), findsNothing);
    expect(find.byIcon(Icons.call_missed), findsNothing);
  });

  testWidgets('a missed call labels the conversation in the DM list',
      (tester) async {
    container
        .read(missedCallsControllerProvider.notifier)
        .record(channelId: 'dm1', callerId: 'u2');

    await openDialog(tester);

    expect(find.text('Missed call'), findsOneWidget);
    expect(find.byIcon(Icons.call_missed), findsOneWidget);
  });

  testWidgets('repeat misses show the count, video misses use the video icon',
      (tester) async {
    final missed = container.read(missedCallsControllerProvider.notifier);
    missed.record(channelId: 'dm1', callerId: 'u2', video: true);
    missed.record(channelId: 'dm1', callerId: 'u2', video: true);

    await openDialog(tester);

    expect(find.text('Missed call (2)'), findsOneWidget);
    expect(find.byIcon(Icons.missed_video_call), findsOneWidget);
    expect(find.byIcon(Icons.call_missed), findsNothing);
  });

  testWidgets('opening the conversation clears the indicator', (tester) async {
    container
        .read(missedCallsControllerProvider.notifier)
        .record(channelId: 'dm1', callerId: 'u2');

    await openDialog(tester);
    expect(find.text('Missed call'), findsOneWidget);

    // Open the conversation, then go back to the list. The conversation shows
    // an endless loading spinner while its (never-arriving) fetch is in flight,
    // so settle isn't an option — pump explicit frames instead.
    await tester.tap(find.text('bob'));
    await tester.pump();
    await tester.pump();
    expect(container.read(missedCallsControllerProvider), isEmpty);

    await tester.tap(find.byTooltip('Back'));
    await tester.pump();

    expect(find.text('bob'), findsOneWidget);
    expect(find.text('Missed call'), findsNothing);
  });

  testWidgets('opening a different conversation keeps the indicator',
      (tester) async {
    container.updateOverrides([
      dmChannelsControllerProvider.overrideWith(
        () => _FakeDmChannels([_dm('dm1', 'bob'), _dm('dm2', 'carol')]),
      ),
    ]);
    container
        .read(missedCallsControllerProvider.notifier)
        .record(channelId: 'dm1', callerId: 'u2');

    await openDialog(tester);
    await tester.tap(find.text('carol'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byTooltip('Back'));
    await tester.pump();

    expect(container.read(missedCallsControllerProvider).keys, ['dm1']);
    expect(find.text('Missed call'), findsOneWidget);
  });
}
