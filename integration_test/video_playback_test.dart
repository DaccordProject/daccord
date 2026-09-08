import 'dart:io';

import 'package:bonfire/features/messaging/views/inline_video_player.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

// Run on a Linux desktop with ffmpeg installed. This exercises real decoding
// and texture rendering; widget tests cannot detect native driver crashes.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('inline video renders, seeks, and reopens on Linux', (
    tester,
  ) async {
    MediaKit.ensureInitialized();
    final directory = await Directory.systemTemp.createTemp('daccord-video-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/clip.mp4';
    final result = await Process.run('ffmpeg', [
      '-v',
      'error',
      '-f',
      'lavfi',
      '-i',
      'testsrc2=size=1024x576:rate=24',
      '-t',
      '6',
      '-c:v',
      'libx264',
      '-pix_fmt',
      'yuv420p',
      path,
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');

    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(AppThemePreset.dark),
          home: Scaffold(
            body: InlineVideoPlayer(url: path, filename: 'clip.mp4'),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.play_circle));
      await tester.pump();
      final controller = tester.widget<Video>(find.byType(Video)).controller;
      final player = controller.player;
      await controller.waitUntilFirstFrameRendered.timeout(
        const Duration(seconds: 20),
      );
      await player.stream.position
          .firstWhere((position) => position >= const Duration(seconds: 1))
          .timeout(const Duration(seconds: 20));
      expect(player.state.width, 1024);
      expect(player.state.height, 576);

      await player.pause();
      await player.seek(const Duration(seconds: 3));
      await player.play();
      await player.stream.position
          .firstWhere((position) => position >= const Duration(seconds: 4))
          .timeout(const Duration(seconds: 20));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  }, skip: !Platform.isLinux);
}
