import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/channels/controllers/dm_channels.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/spaces/utils/message_time.dart';
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

AccordMessage _message(String author, String content, DateTime sentAt) =>
    AccordMessage(
      id: 'm-$content',
      channelId: 'dm1',
      authorId: author,
      content: content,
      timestamp: sentAt.toUtc().toIso8601String(),
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
          () => _FakeDmChannels([
            AccordChannel(
              id: 'dm1',
              type: 'dm',
              recipients: [AccordUser(id: 'u2', username: 'bob')],
            ),
          ]),
        ),
      ],
    );
  });

  tearDown(() => container.dispose());

  testWidgets('row shows the preview and its last-activity time', (
    tester,
  ) async {
    final sentAt = DateTime.now().subtract(const Duration(days: 1));
    container
        .read(dmChannelsControllerProvider('').notifier)
        .setPreview('dm1', _message('u2', 'Near the beach', sentAt));

    await openDialog(tester);

    expect(find.text('bob'), findsOneWidget);
    expect(find.text('Near the beach'), findsOneWidget);
    expect(find.text(conversationTimeString(sentAt)), findsOneWidget);
  });

  testWidgets('a preview without a time shows no time label', (tester) async {
    await openDialog(tester);

    expect(find.text('bob'), findsOneWidget);
    expect(find.text('Yesterday'), findsNothing);
  });

  testWidgets('header actions are compact icon buttons', (tester) async {
    await openDialog(tester);

    expect(find.byTooltip('New group'), findsOneWidget);
    expect(find.byTooltip('Message remote user'), findsOneWidget);
  });
}
