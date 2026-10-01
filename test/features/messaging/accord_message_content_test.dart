import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/messaging/views/box/accord_markdown_box.dart';
import 'package:bonfire/features/messaging/views/box/accord_message_content.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reuses parse inputs on rebuild but refreshes changed channels', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        accordAuthProvider.overrideWithValue(const AccordAuthLoggedOut()),
      ],
    );
    addTearDown(container.dispose);
    final channels = container.read(
      accordChannelsControllerProvider('', 'space').notifier,
    );
    channels.setChannels([
      AccordChannel(id: 'channel', name: 'general', type: 'text'),
    ]);
    final rebuild = ValueNotifier(0);
    addTearDown(rebuild.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(AppThemePreset.dark),
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: rebuild,
              builder: (_, value, _) => AccordMessageContent(
                content: '#general #renamed $value',
                spaceId: 'space',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final syntax = tester
        .widget<AccordMarkdownBox>(find.byType(AccordMarkdownBox))
        .syntaxExtensions;
    expect(find.text('#general'), findsOneWidget);
    expect(find.text('#renamed'), findsNothing);

    rebuild.value++;
    await tester.pump();
    expect(
      tester
          .widget<AccordMarkdownBox>(find.byType(AccordMarkdownBox))
          .syntaxExtensions,
      same(syntax),
    );

    channels.setChannels([
      AccordChannel(id: 'channel', name: 'renamed', type: 'text'),
    ]);
    await tester.pump();
    expect(
      tester
          .widget<AccordMarkdownBox>(find.byType(AccordMarkdownBox))
          .syntaxExtensions,
      isNot(same(syntax)),
    );
    expect(find.text('#general'), findsNothing);
    expect(find.text('#renamed'), findsOneWidget);
  });
}
