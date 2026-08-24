import 'dart:typed_data';

import 'package:bonfire/shared/components/app_lifecycle_ticker_mode.dart';
import 'package:bonfire/shared/components/ticker_aware_circle_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    imageCache.clear();
    imageCache.clearLiveImages();
  });

  testWidgets('disables tickers for every unfocused lifecycle state', (
    tester,
  ) async {
    bool? tickersEnabled;
    await tester.pumpWidget(
      AppLifecycleTickerMode(
        child: Builder(
          builder: (context) {
            tickersEnabled = TickerMode.valuesOf(context).enabled;
            return const SizedBox();
          },
        ),
      ),
    );

    expect(tickersEnabled, isTrue);
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
      expect(tickersEnabled, isFalse, reason: '$state must pause animations');
    }

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tickersEnabled, isTrue);
  });

  testWidgets('freezes an animated GIF on focus loss and resumes it', (
    tester,
  ) async {
    var frame = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: AppLifecycleTickerMode(
          child: Image.memory(
            _animatedGif(),
            errorBuilder: (_, error, _) => throw error,
            frameBuilder: (_, child, currentFrame, _) {
              if (currentFrame != null && currentFrame > frame) {
                frame = currentFrame;
              }
              return child;
            },
          ),
        ),
      ),
    );

    await _pumpUntil(tester, () => frame >= 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    final pausedFrame = frame;

    await tester.pump(const Duration(seconds: 1));
    expect(frame, pausedFrame);
    expect(find.byType(Image), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await _pumpUntil(tester, () => frame > pausedFrame);
    expect(frame, greaterThan(pausedFrame));
  });

  testWidgets('reduced motion still pauses GIFs while focused', (tester) async {
    var frame = -1;
    await tester.pumpWidget(
      AppLifecycleTickerMode(
        child: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Image.memory(
            _animatedGif(),
            errorBuilder: (_, error, _) => throw error,
            frameBuilder: (_, child, currentFrame, _) {
              if (currentFrame != null && currentFrame > frame) {
                frame = currentFrame;
              }
              return child;
            },
          ),
        ),
      ),
    );

    await _pumpUntil(tester, () => frame >= 0);
    final firstFrame = frame;
    await tester.pump(const Duration(seconds: 1));
    expect(frame, firstFrame);
  });

  testWidgets('does not override a disabled ancestor TickerMode', (
    tester,
  ) async {
    bool? tickersEnabled;
    await tester.pumpWidget(
      TickerMode(
        enabled: false,
        child: AppLifecycleTickerMode(
          child: Builder(
            builder: (context) {
              tickersEnabled = TickerMode.valuesOf(context).enabled;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    expect(tickersEnabled, isFalse);
  });

  testWidgets('avatar providers render through a ticker-aware Image', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TickerAwareCircleAvatar(
          radius: 20,
          backgroundColor: Colors.black,
          foregroundImage: MemoryImage(_animatedGif()),
          child: const Text('A'),
        ),
      ),
    );

    expect(find.byType(CircleAvatar), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(
      tester.widget<CircleAvatar>(find.byType(CircleAvatar)).foregroundImage,
      isNull,
    );
  });
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 30 && !condition(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(condition(), isTrue, reason: 'animated image did not advance');
}

Uint8List _animatedGif() {
  image_lib.Image frame(int red, int blue) {
    final result = image_lib.Image(width: 2, height: 2);
    for (var y = 0; y < result.height; y++) {
      for (var x = 0; x < result.width; x++) {
        result.setPixelRgba(x, y, red, 0, blue, 255);
      }
    }
    return result;
  }

  final encoder = image_lib.GifEncoder(repeat: 0)
    ..addFrame(frame(255, 0), duration: 5)
    ..addFrame(frame(0, 255), duration: 5);
  return encoder.finish()!;
}
