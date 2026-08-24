import 'dart:async';
import 'dart:io';

import 'package:bonfire/shared/utils/download_attachment.dart';
import 'package:bonfire/shared/utils/download_attachment_io.dart' as io;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('native attachment downloads', () {
    late Directory downloadsDirectory;

    setUp(() async {
      downloadsDirectory = await Directory.systemTemp.createTemp(
        'daccord-download-test-',
      );
    });

    tearDown(() async {
      if (await downloadsDirectory.exists()) {
        await downloadsDirectory.delete(recursive: true);
      }
    });

    test('allows only HTTP and HTTPS addresses', () async {
      for (final url in [
        'file:///tmp/attachment',
        'ftp://example.com/attachment',
        'data:text/plain,attachment',
        'http:///missing-host',
      ]) {
        final result = await downloadAttachment(url, filename: 'track.mp3');
        expect(result.outcome, DownloadOutcome.failed, reason: url);
        expect(
          result.error,
          'That attachment has no valid address.',
          reason: url,
        );
      }
    });

    test(
      'rejects an oversized advertised Content-Length before reading',
      () async {
        var streamWasRead = false;
        final client = _StreamingClient(
          (_) => http.StreamedResponse(
            Stream<List<int>>.multi((controller) {
              streamWasRead = true;
              controller.add([1]);
              controller.close();
            }),
            200,
            contentLength: 4,
          ),
        );

        final result = await io.downloadAttachmentForTesting(
          'https://example.com/track.mp3',
          filename: 'track.mp3',
          client: client,
          isDesktop: true,
          downloadsDirectory: downloadsDirectory,
          maxBytes: 3,
        );

        expect(result.outcome, DownloadOutcome.failed);
        expect(result.error, 'That attachment is too large to download.');
        expect(streamWasRead, isFalse);
        expect(downloadsDirectory.listSync(), isEmpty);
        expect(client.wasClosed, isTrue);
      },
    );

    test(
      'aborts an oversized chunked desktop response and deletes the file',
      () async {
        var streamWasCancelled = false;
        late StreamController<List<int>> responseBody;
        responseBody = StreamController<List<int>>(
          onListen: () {
            responseBody
              ..add([1, 2])
              ..add([3, 4])
              ..add([5, 6]);
          },
          onCancel: () => streamWasCancelled = true,
        );
        final client = _StreamingClient(
          (_) => http.StreamedResponse(responseBody.stream, 200),
        );

        final result = await io.downloadAttachmentForTesting(
          'https://example.com/track.mp3',
          filename: 'track.mp3',
          client: client,
          isDesktop: true,
          downloadsDirectory: downloadsDirectory,
          maxBytes: 3,
        );

        expect(result.outcome, DownloadOutcome.failed);
        expect(result.error, 'That attachment is too large to download.');
        expect(streamWasCancelled, isTrue);
        expect(downloadsDirectory.listSync(), isEmpty);
        expect(client.wasClosed, isTrue);
      },
    );

    test(
      'caps a chunked mobile response before buffering the excess',
      () async {
        var saveWasCalled = false;
        var streamWasCancelled = false;
        late StreamController<List<int>> responseBody;
        responseBody = StreamController<List<int>>(
          onListen: () {
            responseBody
              ..add([1, 2])
              ..add([3, 4])
              ..add([5, 6]);
          },
          onCancel: () => streamWasCancelled = true,
        );
        final client = _StreamingClient(
          (_) => http.StreamedResponse(responseBody.stream, 200),
        );

        final result = await io.downloadAttachmentForTesting(
          'https://example.com/track.mp3',
          filename: 'track.mp3',
          client: client,
          isDesktop: false,
          maxBytes: 3,
          saveAttachment: (_, _) async {
            saveWasCalled = true;
            return '/saved/track.mp3';
          },
        );

        expect(result.outcome, DownloadOutcome.failed);
        expect(result.error, 'That attachment is too large to download.');
        expect(saveWasCalled, isFalse);
        expect(streamWasCancelled, isTrue);
        expect(client.wasClosed, isTrue);
      },
    );

    test('still passes a bounded mobile response to the save sheet', () async {
      final client = _StreamingClient(
        (_) => http.StreamedResponse(
          Stream.fromIterable([
            [1, 2],
            [3, 4],
          ]),
          200,
          contentLength: 4,
        ),
      );
      String? savedName;
      List<int>? savedBytes;

      final result = await io.downloadAttachmentForTesting(
        'http://example.com/track.mp3',
        filename: 'track.mp3',
        client: client,
        isDesktop: false,
        maxBytes: 4,
        saveAttachment: (filename, bytes) async {
          savedName = filename;
          savedBytes = bytes;
          return '/saved/$filename';
        },
      );

      expect(result.outcome, DownloadOutcome.saved);
      expect(result.path, '/saved/track.mp3');
      expect(savedName, 'track.mp3');
      expect(savedBytes, [1, 2, 3, 4]);
      expect(client.wasClosed, isTrue);
    });
  });
}

class _StreamingClient extends http.BaseClient {
  _StreamingClient(this._respond);

  final http.StreamedResponse Function(http.BaseRequest request) _respond;
  bool wasClosed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      _respond(request);

  @override
  void close() {
    wasClosed = true;
    super.close();
  }
}
