import 'dart:async';
import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/controllers/voice_states.dart';
import 'package:bonfire/features/voice/views/voice_participants.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _userId = '364636253126098944';

class _Voice extends VoiceController {
  @override
  VoiceConnection build() => const VoiceConnection();
}

class _Members extends AccordMembersController {
  _Members(this.members);
  final Map<String, AccordMember> members;

  @override
  Map<String, AccordMember>? build(String serverKey, String spaceId) => members;
}

void main() {
  for (final hasMember in [false, true]) {
    testWidgets(
      'resolves a new voice arrival ${hasMember ? 'with an incomplete member' : 'outside the member page'}',
      (tester) async {
        final response = Completer<http.Response>();
        var fetches = 0;
        final server = AccordServer.fromBaseUrl('https://accord.example.test');
        final client = AccordClient(
          token: 'test-token',
          baseUrl: server.baseUrl,
          gatewayUrl: server.gatewayUrl,
          httpClient: MockClient((request) {
            expect(request.url.path, endsWith('/users/$_userId'));
            fetches++;
            return response.future;
          }),
        );
        addTearDown(client.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              accordAuthProvider.overrideWithValue(
                AccordAuthLoggedIn(
                  client: client,
                  session: AccordSession(
                    server: server,
                    token: 'test-token',
                    userId: 'self',
                    username: 'self',
                  ),
                ),
              ),
              voiceControllerProvider.overrideWith(_Voice.new),
              accordMembersControllerProvider('', 's1').overrideWith(
                () => _Members({
                  if (hasMember) _userId: AccordMember(userId: _userId),
                }),
              ),
            ],
            child: MaterialApp(
              theme: buildAppTheme(AppThemePreset.dark),
              home: const Scaffold(
                body: VoiceParticipantList(channelId: 'c1', spaceId: 's1'),
              ),
            ),
          ),
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(VoiceParticipantList)),
        );
        container
            .read(voiceStatesControllerProvider('').notifier)
            .upsert(AccordVoiceState(userId: _userId, channelId: 'c1'));
        await tester.pump();
        await tester.pump();
        expect(fetches, 1);

        // More gateway flags arrive before the profile: share the same request.
        container
            .read(voiceStatesControllerProvider('').notifier)
            .upsert(
              AccordVoiceState(
                userId: _userId,
                channelId: 'c1',
                selfVideo: true,
              ),
            );
        await tester.pump();
        expect(fetches, 1);
        response.complete(
          http.Response(
            jsonEncode({
              'id': _userId,
              'username': 'new-user',
              'display_name': 'New User',
            }),
            200,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('New User'), findsOneWidget);
        expect(find.text(_userId), findsNothing);
        expect(fetches, 1);
      },
    );
  }
}
