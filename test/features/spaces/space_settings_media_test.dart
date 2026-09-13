import 'dart:typed_data';

import 'package:bonfire/features/spaces/views/accord_space_settings_media.dart';
import 'package:bonfire/shared/components/ticker_aware_circle_avatar.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Widget host(Widget child) => MaterialApp(
  theme: buildAppTheme(AppThemePreset.dark),
  home: Scaffold(
    body: Center(child: SizedBox(width: 320, child: child)),
  ),
);

void main() {
  for (final dpr in [1.0, 2.0]) {
    testWidgets(
      'pending icon replaces the saved URL and removal clears it at ${dpr}x',
      (tester) async {
        tester.view.devicePixelRatio = dpr;
        addTearDown(tester.view.resetDevicePixelRatio);
        final source = img.Image(width: 64, height: 64, numChannels: 4);
        img.fill(source, color: img.ColorRgba8(255, 0, 0, 255));
        final bytes = Uint8List.fromList(img.encodePng(source));
        await tester.pumpWidget(
          host(
            SpaceSettingsIconPreview(
              url: 'https://example.test/old.png',
              pendingBytes: bytes,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final avatar = tester.widget<TickerAwareCircleAvatar>(
          find.byType(TickerAwareCircleAvatar),
        );
        expect(avatar.foregroundImage, isA<MemoryImage>());
        expect((avatar.foregroundImage! as MemoryImage).bytes, same(bytes));
        expect(avatar.child, isNull);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          host(
            SpaceSettingsIconPreview(
              url: 'https://example.test/old.png',
              pendingBytes: bytes,
              removed: true,
            ),
          ),
        );
        expect(
          tester
              .widget<TickerAwareCircleAvatar>(
                find.byType(TickerAwareCircleAvatar),
              )
              .foregroundImage,
          isNull,
        );
        expect(find.byIcon(Icons.image_outlined), findsOneWidget);
      },
    );

    testWidgets('banner preview preserves the exported 16:9 crop at ${dpr}x', (
      tester,
    ) async {
      tester.view.devicePixelRatio = dpr;
      addTearDown(tester.view.resetDevicePixelRatio);
      final bytes = Uint8List.fromList(
        img.encodePng(img.Image(width: 160, height: 90)),
      );
      await tester.pumpWidget(
        host(SpaceSettingsBannerPreview(pendingBytes: bytes)),
      );
      await tester.pumpAndSettle();
      final size = tester.getSize(find.byType(AspectRatio));
      expect(size.width / size.height, closeTo(16 / 9, 0.001));
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.fit, BoxFit.contain);
      expect((image.image as MemoryImage).bytes, same(bytes));
      await tester.pumpWidget(host(const SpaceSettingsBannerPreview()));
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    });
  }
}
