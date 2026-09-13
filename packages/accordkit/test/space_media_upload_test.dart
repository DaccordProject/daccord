import 'package:accordkit/accordkit.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'support/test_helpers.dart';

void main() {
  test('space icon upload reports proxy size errors with status and type',
      () async {
    final rest = mockRest(
      log: [],
      responder: (_) => http.Response(
          '<html>Request Entity Too Large</html>', 413,
          headers: {'content-type': 'text/html'}),
    );
    final result = await SpacesApi(rest)
        .update('space', {'icon': 'data:image/png;base64,eA=='});
    expect(result.ok, isFalse);
    expect(result.statusCode, 413);
    expect(result.error!.code, 'HTTP_413');
    expect(result.error!.message, contains('text/html'));
    expect(result.error!.message, contains('smaller image'));
  });

  test('non-JSON error preserves HTTP context without exposing proxy pages',
      () async {
    final rest = mockRest(
      log: [],
      responder: (_) => http.Response(
          '<html>Private proxy diagnostics</html>', 502,
          headers: {'content-type': 'text/html; charset=utf-8'}),
    );
    final result = await rest.makeRequest('PATCH', '/spaces/s');
    expect(result.statusCode, 502);
    expect(result.error!.message, contains('HTTP 502'));
    expect(result.error!.message, contains('text/html'));
    expect(result.error!.message, isNot(contains('Private proxy')));
  });

  test('HTML success cannot silently acknowledge an unsaved icon', () async {
    final rest = mockRest(
      log: [],
      responder: (_) => http.Response('<html>Sign in</html>', 200,
          headers: {'content-type': 'text/html'}),
    );
    final result = await SpacesApi(rest).update('s', {'icon': null});
    expect(result.ok, isFalse);
    expect(result.error!.message, contains('HTTP 200'));
  });
}
