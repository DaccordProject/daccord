import 'dart:typed_data';

import 'package:bonfire/shared/utils/cropped_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'bounded icon output preserves transparent pixels and is real PNG',
    () async {
      final source = img.Image(width: 1254, height: 1254, numChannels: 4);
      img.fillRect(
        source,
        x1: 627,
        y1: 0,
        x2: 1253,
        y2: 1253,
        color: img.ColorRgba8(255, 0, 0, 255),
      );
      final bytes = await prepareCroppedImage(
        Uint8List.fromList(img.encodePng(source)),
        maxDimension: 512,
      );
      final output = img.decodePng(bytes)!;
      expect(output.width, 512);
      expect(output.height, 512);
      expect(output.getPixel(10, 256).a, 0);
      expect(output.getPixel(500, 256).r, 255);
      expect(output.getPixel(500, 256).a, 255);
      expect(bytes.length, lessThan(1024 * 1024));
    },
  );

  test(
    'banner preparation keeps top and bottom of the selected crop',
    () async {
      final source = img.Image(width: 1600, height: 900);
      img.fillRect(
        source,
        x1: 0,
        y1: 0,
        x2: 1599,
        y2: 449,
        color: img.ColorRgb8(255, 0, 0),
      );
      img.fillRect(
        source,
        x1: 0,
        y1: 450,
        x2: 1599,
        y2: 899,
        color: img.ColorRgb8(0, 0, 255),
      );
      final bytes = await prepareCroppedImage(
        Uint8List.fromList(img.encodeJpg(source)),
        maxDimension: 1024,
      );
      final output = img.decodePng(bytes)!;
      expect(output.width, 1024);
      expect(output.height, 576);
      expect(output.getPixel(512, 10).r, greaterThan(240));
      expect(output.getPixel(512, 560).b, greaterThan(240));
    },
  );

  test('small images are not enlarged', () async {
    final source = img.Image(width: 32, height: 18);
    final bytes = await prepareCroppedImage(
      Uint8List.fromList(img.encodePng(source)),
      maxDimension: 1024,
    );
    final output = img.decodePng(bytes)!;
    expect(output.width, 32);
    expect(output.height, 18);
  });
}
