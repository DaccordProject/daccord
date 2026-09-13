import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Encodes the selected crop as PNG, preserving alpha and its full framing.
/// Bounds large uploads without upscaling small sources. The crop package may
/// preserve the source JPEG/BMP encoding, even when the caller names it .png.
Future<Uint8List> prepareCroppedImage(
  Uint8List bytes, {
  int? maxDimension,
}) async {
  assert(maxDimension == null || maxDimension > 0);
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  try {
    final scale = maxDimension == null
        ? 1.0
        : math.min(
            1.0,
            maxDimension / math.max(descriptor.width, descriptor.height),
          );
    final codec = await descriptor.instantiateCodec(
      targetWidth: math.max(1, (descriptor.width * scale).round()),
      targetHeight: math.max(1, (descriptor.height * scale).round()),
    );
    try {
      final frame = await codec.getNextFrame();
      try {
        final data = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (data == null) throw StateError('Could not encode cropped image');
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  } finally {
    descriptor.dispose();
    buffer.dispose();
  }
}
