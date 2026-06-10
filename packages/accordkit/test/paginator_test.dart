import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'support/test_helpers.dart';

void main() {
  group('AccordPaginator', () {
    test('fromResult deserializes items and tracks cursor', () async {
      final rest = mockRest(log: [], responder: (_) => jsonData([]));
      final result = RestResult.success(
        200,
        [
          {'id': '1', 'username': 'a'},
        ],
        {'after': '1', 'has_more': true},
      );
      final p = AccordPaginator.fromResult(result, rest, '/users', {},
          fromJson: AccordUser.fromJson);
      expect(p.items.single, isA<AccordUser>());
      expect(p.hasMore, isTrue);
    });

    test('next fetches following page with after cursor', () async {
      final log = <CapturedRequest>[];
      final rest = mockRest(
        log: log,
        responder: (_) => http.Response(
          jsonEncode({
            'data': [
              {'id': '2', 'username': 'b'},
            ],
            'cursor': {'after': '', 'has_more': false},
          }),
          200,
        ),
      );
      final first = RestResult.success(
        200,
        [
          {'id': '1', 'username': 'a'},
        ],
        {'after': '1', 'has_more': true},
      );
      final p = AccordPaginator.fromResult(first, rest, '/users', {},
          fromJson: AccordUser.fromJson);
      final next = await p.next();
      expect(log.single.url.queryParameters['after'], '1');
      expect((next.items.single as AccordUser).id, '2');
      expect(next.hasMore, isFalse);
    });
  });
}
