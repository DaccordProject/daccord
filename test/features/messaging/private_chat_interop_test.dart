import 'dart:convert';
import 'dart:io';
import 'package:accordkit/accordkit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'private_chat_encryption_test.dart' show MemoryKeys;

void main() {
  test(
    'shared Dart/Rust fixture authenticates and decrypts its body and file',
    () async {
      final fixture =
          jsonDecode(await File('test/fixtures/e2ee_v1.json').readAsString())
              as Map;
      final store = MemoryKeys();
      final scope = base64Url.encode(
        utf8.encode('https://chat.test/api/v1|bob'),
      );
      store.values['e2ee.v1.$scope.identity'] = jsonEncode({
        'exchange_private': base64Encode(List.filled(32, 8)),
        'signing_private': base64Encode(List.filled(32, 8)),
      });
      final client = AccordClient(
        token: 'bob',
        tokenType: 'Bearer',
        baseUrl: 'https://chat.test',
        encryptionUserId: 'bob',
        encryptionStore: store,
        httpClient: MockClient((r) async {
          final data = r.method == 'PUT'
              ? jsonDecode(r.body)
              : {
                  'channel_id': 'chat',
                  'self_user_id': 'bob',
                  'participants': [
                    for (final e in (fixture['identities'] as Map).entries)
                      {
                        'user_id': e.key,
                        'wire_user_id': e.key,
                        'current': true,
                        'identity': e.value,
                      },
                  ],
                };
          return http.Response(jsonEncode({'data': data}), 200);
        }),
      );
      try {
        final encryptedFile = base64Decode(fixture['encrypted_file'] as String);
        final message = await client.encryption!.decrypt(
          AccordMessage(
            id: 'fixture',
            channelId: 'chat',
            authorId: 'alice',
            content: fixture['content'] as String,
            attachments: [
              AccordAttachment(
                id: 'file',
                filename: 'attachment-0.bin',
                size: encryptedFile.length,
              ),
            ],
          ),
        );
        expect(message.encryptionError, isNull);
        expect(message.content, fixture['expected_content']);
        expect(
          utf8.decode(
            await client.encryption!.decryptAttachment(
              message.attachments.single,
              encryptedFile,
            ),
          ),
          fixture['expected_file'],
        );
      } finally {
        await client.dispose();
      }
    },
  );
}
