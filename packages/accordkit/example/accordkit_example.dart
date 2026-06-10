// ignore_for_file: avoid_print
import 'package:accordkit/accordkit.dart';

/// A minimal echo bot: connects to the gateway and replies "pong" to "!ping".
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

  client.onReady.listen((data) {
    print('Ready! session=${data['session_id']}');
  });

  client.onMessageCreate.listen((message) async {
    if (message.content == '!ping') {
      await client.messages.create(message.channelId, {'content': 'pong'});
    }
  });

  client.onDisconnected.listen((info) {
    print('Disconnected: ${info.code} ${info.reason}');
  });

  client.login();

  // A REST call works independently of the gateway:
  final me = await client.users.getMe();
  if (me.ok) {
    print('Logged in as ${(me.data as AccordUser).username}');
  } else {
    print('Failed to fetch self: ${me.error}');
  }
}
