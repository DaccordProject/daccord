import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/src/internal/events.dart';
import 'package:livekit_client/src/utils.dart';

void main() {
  group('Utils.redactUri', () {
    test('redacts all access token values and preserves useful URL details', () {
      const firstToken = 'first.secret.token';
      const secondToken = 'second.secret.token';
      final uri = Uri.parse(
        'wss://voice.example.com/rtc?access_token=$firstToken&protocol=15&access_token=$secondToken#diagnostics',
      );

      final redacted = Utils.redactUri(uri);
      final formatted = redacted.toString();

      expect(formatted, isNot(contains(firstToken)));
      expect(formatted, isNot(contains(secondToken)));
      expect(redacted.scheme, 'wss');
      expect(redacted.host, 'voice.example.com');
      expect(redacted.path, '/rtc');
      expect(redacted.queryParametersAll['access_token'], ['REDACTED', 'REDACTED']);
      expect(redacted.queryParameters['protocol'], '15');
      expect(redacted.fragment, 'diagnostics');
    });

    test('leaves URLs without an access token unchanged', () {
      final uri = Uri.parse('wss://voice.example.com/rtc?protocol=15');

      expect(Utils.redactUri(uri), same(uri));
    });
  });

  test('SignalTokenUpdatedEvent formatting never includes the token', () {
    const token = 'updated.secret.token';
    const event = SignalTokenUpdatedEvent(token: token);

    expect(event.toString(), 'SignalTokenUpdatedEvent(token: REDACTED)');
    expect(event.toString(), isNot(contains(token)));
  });
}
