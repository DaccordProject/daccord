import 'package:bonfire/features/messaging/views/inline_video_player.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
      theme: buildAppTheme(AppThemePreset.dark),
      home: Scaffold(body: child),
    );

/// iOS ships without media_kit's libmpv (its Mpv.framework references
/// fork/execve and OpenGL ES, which got 0.2.6 rejected under App Store
/// guideline 2.5.1), so video there decodes via AVFoundation — which handles
/// far fewer containers than libmpv. These cover the gate that keeps an
/// unplayable container from opening a player that would fail on the first
/// frame.
void main() {
  Widget player(String url, {String filename = 'clip'}) =>
      _host(InlineVideoPlayer(url: url, filename: filename));

  group('InlineVideoPlayer container gate', () {
    testWidgets('offers playback for every container off iOS', (tester) async {
      await tester.pumpWidget(player('https://cdn.example/a.mkv'));
      expect(find.byIcon(Icons.play_circle), findsOneWidget);
      expect(find.byIcon(Icons.videocam_off), findsNothing);
    });

    testWidgets('offers playback on iOS for an AVFoundation container',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await tester.pumpWidget(player('https://cdn.example/a.mp4?ex=deadbeef'));
      expect(find.byIcon(Icons.play_circle), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('refuses a container AVFoundation cannot demux on iOS',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await tester.pumpWidget(player('https://cdn.example/a.mkv'));
      expect(find.byIcon(Icons.videocam_off), findsOneWidget);
      expect(find.byIcon(Icons.play_circle), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('falls back to the filename when the URL has no extension',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await tester.pumpWidget(
        player('https://cdn.example/attachments/1', filename: 'clip.mov'),
      );
      expect(find.byIcon(Icons.play_circle), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('refuses an embed page URL on iOS', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await tester.pumpWidget(
        player('https://example.com/watch', filename: 'Some video title'),
      );
      expect(find.byIcon(Icons.videocam_off), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
