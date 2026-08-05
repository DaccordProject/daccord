import 'dart:convert';
import 'dart:typed_data';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/messaging/views/message_pane/message_pane.dart';
import 'package:bonfire/features/server/controllers/server_limits.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Composer attachment behaviour, driven through the real [MessagePane].
///
/// Two things are under test here, both from #196:
///
/// - a rejection (oversize, unreadable, too many, picker blew up) has to end up
///   *on screen*. The reporter described "nothing happens", and the picker call
///   really could throw out of an unawaited `onPressed`, which shows the user
///   precisely nothing;
/// - the limits enforced are the connected server's (`GET /settings`), not the
///   compiled-in fallbacks.

const _channelId = 'c1';
const _selfId = 'u1';

class _FakeSettingsController extends SettingsController {
  @override
  AccordSettings build() => const AccordSettings();
}

/// A [FilePicker] whose `pickFiles` does whatever the test says.
///
/// Subclassing [FilePicker] is enough for `FilePicker.platform =`: the base
/// constructor passes the package's own verification token.
class _FakeFilePicker extends FilePicker {
  _FakeFilePicker(this.onPick);

  final Future<FilePickerResult?> Function() onPick;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    @Deprecated('allowCompression is deprecated and has no effect.')
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) {
    // The composer must not narrow the picker: the server has no type
    // allow-list, so filtering here would hide legitimate files.
    expect(type, FileType.any);
    expect(allowedExtensions, isNull);
    expect(withData, isTrue);
    return onPick();
  }
}

PlatformFile _file(String name, {int bytes = 16}) => PlatformFile(
      name: name,
      size: bytes,
      bytes: Uint8List(bytes),
    );

class _Harness {
  _Harness({Map<String, Object?>? settings, this.sendStatus = 200}) {
    final responder = MockClient((request) async {
      final path = request.url.path;
      requests.add('${request.method} $path');
      if (path.endsWith('/settings')) {
        if (settings == null) return http.Response('{"message":"no"}', 403);
        return http.Response(
          jsonEncode({'data': settings}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (path.contains('/messages/upload')) {
        return http.Response(
          sendStatus == 200
              ? jsonEncode({
                  'id': 'm9',
                  'channel_id': _channelId,
                  'author_id': _selfId,
                  'content': '',
                  'timestamp': '2026-01-01T10:00:00Z',
                })
              : jsonEncode({'message': 'Payload too large'}),
          sendStatus,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        '[]',
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final server = AccordServer.fromBaseUrl('https://accord.example.test');
    client = AccordClient(
      token: 'test-token',
      tokenType: 'Bearer',
      baseUrl: server.baseUrl,
      gatewayUrl: server.gatewayUrl,
      cdnUrl: server.cdnUrl,
      httpClient: responder,
    );
    container = ProviderContainer(
      overrides: [
        accordAuthProvider.overrideWithValue(
          AccordAuthLoggedIn(
            client: client,
            session: AccordSession(
              server: server,
              token: 'test-token',
              userId: _selfId,
              username: 'self',
            ),
          ),
        ),
        settingsControllerProvider.overrideWith(_FakeSettingsController.new),
      ],
    );
  }

  final int sendStatus;
  final List<String> requests = [];
  late final AccordClient client;
  late final ProviderContainer container;

  Widget get app => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(AppThemePreset.dark),
          home: const Scaffold(
            body: MessagePane(channel: null, channelId: _channelId,
                spaceId: null),
          ),
        ),
      );

  void dispose() => client.dispose();
}

Future<void> _tick(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<_Harness> _pump(
  WidgetTester tester, {
  Map<String, Object?>? settings,
  int sendStatus = 200,
}) async {
  final harness = _Harness(settings: settings, sendStatus: sendStatus);
  addTearDown(harness.dispose);
  await tester.pumpWidget(harness.app);
  await _tick(tester);
  return harness;
}

/// Taps the composer's attach button.
Future<void> _tapAttach(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.add_circle_outline));
  await _tick(tester);
}

/// Every visible text in the tree containing [needle] — the composer's error is
/// rendered by `InlineError`, so this asserts what the user can actually read.
Finder _visibleText(String needle) => find.byWidgetPredicate(
      (w) => w is Text && (w.data ?? '').contains(needle),
    );

void main() {
  late FilePicker? original;

  setUp(() {
    original = null;
    try {
      original = FilePicker.platform;
    } catch (_) {
      // Never initialised in a unit test; nothing to restore.
    }
  });

  tearDown(() {
    if (original != null) FilePicker.platform = original!;
  });

  testWidgets('a picker that throws surfaces an error instead of nothing',
      (tester) async {
    // The #196 "nothing happens" path: on Windows the legacy picker can throw,
    // and the throw escaped an unawaited callback, leaving no trace on screen.
    FilePicker.platform = _FakeFilePicker(
      () async => throw Exception('GetOpenFileNameW failed'),
    );
    await _pump(tester);
    await _tapAttach(tester);

    expect(_visibleText("Couldn't open the file picker"), findsOneWidget);
    expect(_visibleText('GetOpenFileNameW failed'), findsOneWidget);
  });

  testWidgets('a picker that returns nothing leaves no error', (tester) async {
    FilePicker.platform = _FakeFilePicker(() async => null);
    await _pump(tester);
    await _tapAttach(tester);
    expect(_visibleText("Couldn't open"), findsNothing);
  });

  testWidgets('an oversize file is named in the composer, not dropped',
      (tester) async {
    FilePicker.platform = _FakeFilePicker(
      () async => FilePickerResult([_file('podcast.mp3', bytes: 4096)]),
    );
    // Server says 1 KB, well under the 25 MB compiled-in fallback.
    await _pump(tester, settings: const {'max_attachment_size': 1024});
    await _tapAttach(tester);

    expect(_visibleText('podcast.mp3'), findsWidgets);
    expect(_visibleText('the limit is 1 KB'), findsOneWidget);
  });

  testWidgets('an unreadable file is named in the composer', (tester) async {
    // bytes == null is what a OneDrive placeholder that failed to hydrate
    // looks like coming back from the Windows picker.
    FilePicker.platform = _FakeFilePicker(
      () async => FilePickerResult([
        PlatformFile(name: 'cloud.mp3', size: 4096),
      ]),
    );
    await _pump(tester);
    await _tapAttach(tester);

    expect(_visibleText("couldn't be read"), findsOneWidget);
  });

  testWidgets("the server's per-message count limit is enforced and explained",
      (tester) async {
    FilePicker.platform = _FakeFilePicker(
      () async => FilePickerResult([
        _file('a.png'),
        _file('b.png'),
        _file('c.png'),
      ]),
    );
    await _pump(tester, settings: const {'max_attachments_per_message': 2});
    await _tapAttach(tester);

    expect(_visibleText('at most 2 files per message'), findsOneWidget);
    // The first two still attached — a full batch isn't lost over one extra.
    expect(_visibleText('a.png'), findsOneWidget);
    expect(_visibleText('b.png'), findsOneWidget);
  });

  testWidgets('the attach button disables once the count limit is reached',
      (tester) async {
    FilePicker.platform = _FakeFilePicker(
      () async => FilePickerResult([_file('a.png')]),
    );
    await _pump(tester, settings: const {'max_attachments_per_message': 1});
    await _tapAttach(tester);

    final button = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.add_circle_outline),
        matching: find.byType(IconButton),
      ),
    );
    expect(button.onPressed, isNull);
    expect(button.tooltip, contains('Attachment limit reached'));
  });

  testWidgets('a failed upload shows the server error and keeps the file',
      (tester) async {
    FilePicker.platform = _FakeFilePicker(
      () async => FilePickerResult([_file('song.mp3')]),
    );
    await _pump(tester, sendStatus: 413);
    await _tapAttach(tester);
    expect(_visibleText('song.mp3'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.send));
    await _tick(tester);

    expect(_visibleText('Payload too large'), findsOneWidget);
    // The attachment comes back so the send can be retried.
    expect(_visibleText('song.mp3'), findsOneWidget);
  });

  testWidgets('falls back to the compiled-in limits when /settings 403s',
      (tester) async {
    FilePicker.platform = _FakeFilePicker(
      () async => FilePickerResult([_file('small.png')]),
    );
    final harness = await _pump(tester); // settings: null ⇒ 403
    await _tapAttach(tester);

    expect(harness.requests, contains('GET /api/v1/settings'));
    expect(
      harness.container.read(serverLimitsControllerProvider).fromServer,
      isFalse,
    );
    // A small file still attaches on the fallback limits.
    expect(_visibleText('small.png'), findsOneWidget);
    expect(_visibleText('the limit is'), findsNothing);
  });
}
