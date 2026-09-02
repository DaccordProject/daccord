# AccordKit for Dart

[![Dart](https://img.shields.io/badge/Dart-3.0%2B-0175C2?logo=dart)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

An [Accord protocol](https://daccord.gg) client library for Dart. AccordKit
gives you a typed REST client, a resilient gateway WebSocket client (with
automatic heartbeating, resume, and reconnect), and data models for building
bots, tools, and apps against [Daccord](https://daccord.gg) servers.

This is a Dart port of the GDScript `accordkit` addon and tracks the same API
surface and wire behaviour.

## Features

- **REST client** covering every endpoint group: users, spaces, channels,
  messages, members, roles, bans, reports, invites, emojis, soundboard,
  reactions, interactions, plugins, applications, auth, voice, audit logs,
  admin, and the master-server directory.
- **Gateway client** with IDENTIFY/RESUME handshake, heartbeating, exponential
  backoff reconnect, and ~50 typed event streams.
- **Typed models** with lenient JSON parsing (`fromJson`) and `toJson`.
- **Voice manager** that ties the voice REST endpoints to gateway voice events.
- **Helpers** for snowflakes, CDN URLs, permissions, intents, multipart
  uploads, and cursor pagination.
- **Testable by design** — inject an `http.Client` for REST and a connection
  factory for the gateway.

## Installation

Add the dependency to your `pubspec.yaml`:

```yaml
dependencies:
  accordkit:
    git:
      url: https://github.com/DaccordProject/accordkit-dart.git
```

Then run `dart pub get` (or `flutter pub get`).

## Quick start

```dart
import 'package:accordkit/accordkit.dart';

Future<void> main() async {
  final client = AccordClient(
    token: 'YOUR_BOT_TOKEN',
    tokenType: 'Bot',
    baseUrl: 'https://your.daccord.server',
    gatewayUrl: 'wss://your.daccord.server/ws',
    intents: [
      GatewayIntents.spaces,
      GatewayIntents.messages,
      GatewayIntents.messageContent,
    ],
  );

  client.onMessageCreate.listen((message) async {
    if (message.content == '!ping') {
      await client.messages.create(message.channelId, {'content': 'pong'});
    }
  });

  client.login();
}
```

See [`example/accordkit_example.dart`](example/accordkit_example.dart) for a
complete sample.

## REST

Every endpoint group hangs off `AccordClient`, and every call returns a
`RestResult`:

```dart
final result = await client.spaces.fetch('space_id');
if (result.ok) {
  final space = result.data as AccordSpace;
  print(space.name);
} else {
  print('Error: ${result.error}'); // AccordError(code, message)
}
```

Endpoint paths are always bare (`/channels/…`); the `/api/v1` prefix belongs to
the `AccordRest` base URL, which `AccordClient` builds via `config.apiUrl()`.
`DirectoryApi` follows the same rule even though it targets the master server
rather than an instance — point it elsewhere by building an `AccordRest` for
`<master>` + `AccordConfig.apiBasePath`.

`RestResult.data` is the deserialized model (or list of models) on success, and
`RestResult.error` is an `AccordError` on failure. Cursor-paginated endpoints
expose `RestResult.hasMore` and `RestResult.cursor`; wrap them with
`AccordPaginator` to page through results:

```dart
final first = await client.messages.list('channel_id', query: {'limit': 50});
var page = AccordPaginator.fromResult(
  first, client.rest, '/channels/channel_id/messages', {'limit': 50},
  fromJson: AccordMessage.fromJson,
);
while (page.hasMore) {
  page = await page.next();
}
```

### Timeouts

Every REST attempt is bounded by `AccordConfig.defaultRequestTimeout` (30s), so
a server that accepts a connection and then never answers surfaces as an
ordinary `RestResult` failure rather than a future that never completes.
Override it per client:

```dart
final client = AccordClient(
  baseUrl: 'https://your.accord.server',
  requestTimeout: const Duration(seconds: 10),
);
```

The deadline applies **per attempt**, not across the built-in 429 retry loop, so
a server-dictated `Retry-After` pause never counts against the next attempt's
budget.

Multipart file uploads use a separate, longer budget —
`AccordConfig.defaultUploadTimeout` (5 minutes) — since an upload's duration
scales with attachment size and connection speed rather than server response
latency. Override it independently with `uploadTimeout`:

```dart
final client = AccordClient(
  baseUrl: 'https://your.accord.server',
  uploadTimeout: const Duration(minutes: 10),
);
```

### File uploads

```dart
await client.messages.createWithAttachments(
  'channel_id',
  {'content': 'Here is a file'},
  [
    {
      'filename': 'image.png',
      'content': bytes,            // List<int> / Uint8List
      'content_type': 'image/png',
    },
  ],
);
```

## Gateway events

Subscribe to typed broadcast streams on the client (or on `client.gateway`):

```dart
client.onReady.listen((data) => print('session ${data['session_id']}'));
client.onMessageCreate.listen((m) => print('${m.authorId}: ${m.content}'));
client.onPresenceUpdate.listen((p) => print('${p.userId} is ${p.status}'));

// Catch-all for any event:
client.onRawEvent.listen((e) => print('event ${e.type}'));
```

Lifecycle and presence:

```dart
client.login();                       // open the gateway
client.updatePresence('online', activity: {'name': 'a game'});
await client.logout();                // close the gateway
```

The gateway reconnects automatically with exponential backoff and resumes the
session when possible. Fatal close codes (e.g. authentication failures) stop
reconnection.

## Voice

```dart
final vm = client.voiceManager;
vm.onVoiceConnected.listen((info) => print('joined ${info.channelId}'));
vm.onVoiceDisconnected.listen((channelId) => print('left $channelId'));

await vm.join('voice_channel_id', selfMute: false);
await vm.leave();
```

## Helpers

```dart
// Snowflakes
final created = AccordSnowflake.decodeToDateTime(message.id);

// CDN URLs
final url = AccordCDN.avatar(user.id, user.avatar!, cdnUrl: client.config.cdnUrl);

// Permissions
if (AccordPermission.has(member.roles, AccordPermission.banMembers)) { /* ... */ }
```

## Testing your integration

The REST client accepts any `http.Client`, and the gateway accepts a
connection factory, so you can test without real network access:

```dart
final client = AccordClient(
  token: 'tok',
  httpClient: myMockHttpClient,        // package:http/testing.dart MockClient
  connectionFactory: myFakeConnection, // GatewayConnection factory
);
```

## Development

```bash
dart pub get
dart analyze
dart test
```

## License

[MIT](LICENSE) © Daccord Project
