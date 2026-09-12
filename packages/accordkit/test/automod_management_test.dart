import 'dart:typed_data';
import 'package:accordkit/accordkit.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'support/test_helpers.dart';

void main() {
  test('management routes encode IDs, scope, filters and audit reasons',
      () async {
    final log = <CapturedRequest>[];
    final api =
        AutomodApi(mockRest(log: log, responder: (_) => jsonData(null)));
    await api.setPolicy('*', {'enabled': true, 'rules': []});
    await api.listUploads('space', status: 'rejected', before: '123');
    await api.review('upload/id', 'release', 'Reviewed');
    await api.blockAttachment('space', 'file', 'Repeated upload');
    await api.blockHash('space', 'abcd', 'Blocked');
    await api.unblockHash('space', 'abcd');
    await api.resetPolicy('space');
    expect(log[0].method, 'PUT');
    expect(log[0].jsonBody, {'enabled': true, 'rules': []});
    expect(log[1].url.queryParameters, {'status': 'rejected', 'before': '123'});
    expect(log[2].url.pathSegments.last, 'upload/id');
    expect(log[2].jsonBody, {'action': 'release', 'reason': 'Reviewed'});
    expect(log[3].url.path, '/api/v1/automod/space/attachments/file/block');
    expect(log[4].method, 'PUT');
    expect(log[5].method, 'DELETE');
    expect(log[6].url.path, '/api/v1/automod/space/policy');
  });
  test('moderator mutations do not silently retry 429', () async {
    final log = <CapturedRequest>[];
    final api = AutomodApi(mockRest(
        log: log,
        responder: (_) => jsonError('rate_limited', 'Wait', status: 429)));
    expect((await api.review('u', 'reject', 'Reason')).statusCode, 429);
    expect(log, hasLength(1));
  });
  test('private content uses authenticated binary API and bounds buffering',
      () async {
    final log = <CapturedRequest>[];
    final rest = mockRest(
        log: log, responder: (_) => http.Response.bytes([0, 255, 1], 200));
    final result = await AutomodApi(rest).getContent('u');
    expect(result.data, isA<Uint8List>());
    expect(result.data, [0, 255, 1]);
    expect(log.single.url.path, '/api/v1/automod/uploads/u/content');
    expect(log.single.headers['authorization'], 'Bot test-token');
    final limited = await rest.makeRawRequest('/private', maxBytes: 2);
    expect(limited.ok, isFalse);
    expect(limited.error?.message, contains('download limit'));
  });
  test('expired evidence remains an error without public fallback', () async {
    final log = <CapturedRequest>[];
    final api = AutomodApi(
        mockRest(log: log, responder: (_) => http.Response('', 410)));
    expect((await api.getContent('expired')).statusCode, 410);
    expect(log, hasLength(1));
  });
  test('attachment digest remains optional for older servers', () {
    final legacy = AccordAttachment.fromJson({'id': 'a', 'filename': 'x'});
    expect(legacy.contentHash, isNull);
    expect(legacy.toJson().containsKey('content_hash'), isFalse);
    final current =
        AccordAttachment.fromJson({'id': 'a', 'content_hash': 'hash'});
    expect(current.toJson()['content_hash'], 'hash');
  });
  test('private evidence disables redirect following', () async {
    var attempts = 0;
    final rest = AccordRest('https://example.test/api/v1', token: 'secret',
        client: MockClient.streaming((request, stream) async {
      attempts++;
      expect(request.followRedirects, isFalse);
      return http.StreamedResponse(Stream.value(<int>[]), 302,
          headers: {'location': 'https://elsewhere.test/file'});
    }));
    expect((await AutomodApi(rest).getContent('u')).ok, isFalse);
    expect(attempts, 1);
  });
}
