import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/messaging/controllers/thread_replies.dart';
import 'package:bonfire/features/messaging/utils/send_cooldown.dart';
import 'package:bonfire/features/messaging/views/post_composer_dialog.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class QuietSettings extends SettingsController {
  @override
  AccordSettings build() => const AccordSettings(convertEmoticons: false);
}

void main() {
  test('thread reply preserves retry duration and makes one attempt', () async {
    var attempts = 0;
    final client = AccordClient(
      baseUrl: 'https://example.test',
      gatewayUrl: 'wss://example.test/ws',
      cdnUrl: 'https://example.test/cdn',
      httpClient: MockClient((_) async {
        attempts++;
        return http.Response(
          '{"error":{"code":"rate_limited","message":"Wait","retry_after":12}}',
          429,
        );
      }),
    );
    addTearDown(client.dispose);
    final container = ProviderContainer(
      overrides: [
        accordAuthProvider.overrideWithValue(const AccordAuthLoggedOut()),
      ],
    );
    addTearDown(container.dispose);
    final failure = await container
        .read(threadRepliesControllerProvider('', 'c', 'root').notifier)
        .sendDetailed(client, 'reply');
    expect(failure?.rateLimited, isTrue);
    expect(failure?.retryAfter, const Duration(seconds: 12));
    expect(attempts, 1);
  });
  testWidgets(
    'post preserves draft and blocks repeat submit until retry expires',
    (tester) async {
      final client = AccordClient(
        baseUrl: 'https://example.test',
        gatewayUrl: 'wss://example.test/ws',
        cdnUrl: 'https://example.test/cdn',
      );
      addTearDown(client.dispose);
      var attempts = 0;
      var now = DateTime.utc(2026);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsControllerProvider.overrideWith(QuietSettings.new),
            accordAuthProvider.overrideWithValue(
              AccordAuthLoggedIn(
                client: client,
                session: AccordSession(
                  server: AccordServer.fromBaseUrl('https://example.test'),
                  token: 't',
                  userId: 'u',
                  username: 'user',
                ),
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: PostComposerDialog(
                title: 'New post',
                now: () => now,
                submitLabel: 'Post',
                bodyLabel: 'Body',
                initialTitle: 'My post',
                initialBody: 'Keep this draft',
                onSubmit: (_, _, _) async {
                  attempts++;
                  return 'Wait';
                },
                sendFailure: () => const SendFailure(
                  'Wait',
                  retryAfter: Duration(seconds: 3),
                  rateLimited: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Post'));
      await tester.pump();
      expect(attempts, 1);
      expect(find.text('Keep this draft'), findsOneWidget);
      expect(find.textContaining('try again in 3s'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Post'))
            .onPressed,
        isNull,
      );
      now = now.add(const Duration(seconds: 4));
      await tester.pump(const Duration(seconds: 4));
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Post'))
            .onPressed,
        isNotNull,
      );
      expect(attempts, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
