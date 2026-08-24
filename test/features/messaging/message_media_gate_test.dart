import 'package:bonfire/features/messaging/views/message_media_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('third-party image is not built until explicit consent', (
    tester,
  ) async {
    final builtUrls = <String>[];
    await tester.pumpWidget(
      _host(
        MessageMediaGate(
          source: 'https://tracker.example/pixel.png',
          trustedBaseUrl: 'https://chat.example/cdn',
          builder: (_, url) {
            builtUrls.add(url);
            return const Text('image built');
          },
        ),
      ),
    );

    expect(builtUrls, isEmpty);
    expect(
      find.text('Load external image from tracker.example'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('load-external-message-image')));
    await tester.pump();

    expect(builtUrls, ['https://tracker.example/pixel.png']);
    expect(find.text('image built'), findsOneWidget);
  });

  testWidgets('trusted CDN image is built without a consent prompt', (
    tester,
  ) async {
    final builtUrls = <String>[];
    await tester.pumpWidget(
      _host(
        MessageMediaGate(
          source: '/cdn/attachments/image.png',
          trustedBaseUrl: 'https://chat.example/cdn',
          builder: (_, url) {
            builtUrls.add(url);
            return const Text('image built');
          },
        ),
      ),
    );

    expect(builtUrls, ['https://chat.example/cdn/attachments/image.png']);
    expect(
      find.byKey(const ValueKey('load-external-message-image')),
      findsNothing,
    );
  });

  testWidgets('local and custom URIs never reach the image builder', (
    tester,
  ) async {
    var builds = 0;
    for (final source in [
      'file:///tmp/private.png',
      'resource:assets/private.png',
      r'\\server\share\pixel.png',
      'custom://pixel.png',
    ]) {
      await tester.pumpWidget(
        _host(
          MessageMediaGate(
            source: source,
            trustedBaseUrl: 'https://chat.example/cdn',
            builder: (_, _) {
              builds++;
              return const Text('image built');
            },
          ),
        ),
      );
      expect(find.text('image built'), findsNothing, reason: source);
      expect(
        find.byKey(const ValueKey('load-external-message-image')),
        findsNothing,
        reason: source,
      );
    }
    expect(builds, 0);
  });
}
