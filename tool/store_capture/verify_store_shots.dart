// Checks the App Store screenshot set against the rules in
// `docs/app-store-deploy.md` ("Guideline 2.3.10"). Run after a regeneration:
//
//     dart run tool/store_capture/verify_store_shots.dart
//
// Three checks, none of which needs a human eye:
//
//  1. Exact delivery sizes, read from each PNG's IHDR chunk rather than from a
//     decoder that might normalise them.
//  2. Edge flatness on every inner capture: the device frame shows a capture
//     whole, so a glyph sliced by the capture's own edge is a glyph sliced in
//     the shipped screenshot — guideline 2.2's "half-visible" finding. Text and
//     icons produce many colour transitions along an edge line; a pane boundary
//     produces a handful.
//  3. The tablet captures really are landscape and really are the size the
//     template's `--screen-ar` claims.
//
// It cannot judge whether a screenshot is *good*; look at the renders too.

import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Apple's fixed delivery sizes.
const _iphoneSize = (1284, 2778);
const _ipadSize = (2048, 2732);

/// The tablet capture canvas: a 13" iPad landscape at 2x.
const _tabletCapture = (2732, 2048);

/// The phone capture canvases (`t-06` is deliberately shorter — see the doc).
const _phoneCaptureWidth = 740;

/// How many colour transitions an edge line may contain before it is judged to
/// be cutting through content rather than crossing a pane boundary.
const _maxEdgeTransitions = 12;

/// Per-channel difference that counts as a transition.
const _transitionThreshold = 24;

int _failures = 0;

void _fail(String message) {
  _failures++;
  stderr.writeln('FAIL  $message');
}

void _ok(String message) => stdout.writeln('ok    $message');

void main(List<String> args) {
  final root = Directory.current.path;
  final generator = p.join(root, 'store-media', 'ios-generator');

  _checkSizes(p.join(root, 'store-media', 'ios-iphone-6.5'), _iphoneSize);
  _checkSizes(p.join(root, 'store-media', 'ios-ipad-13'), _ipadSize);

  final inner = Directory(p.join(generator, 'inner'));
  if (!inner.existsSync()) {
    _fail('no inner captures at ${inner.path}');
  } else {
    final files =
        inner
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.png'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      _checkCapture(file);
    }
  }

  if (_failures > 0) {
    stderr.writeln('\n$_failures check(s) failed.');
    exit(1);
  }
  stdout.writeln('\nAll checks passed.');
}

void _checkSizes(String dir, (int, int) expected) {
  final directory = Directory(dir);
  if (!directory.existsSync()) {
    _fail('missing directory $dir');
    return;
  }
  final files =
      directory
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.png'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty) _fail('no PNGs in $dir');
  for (final file in files) {
    final size = _ihdrSize(file);
    final name = p.join(p.basename(dir), p.basename(file.path));
    if (size != expected) {
      _fail(
        '$name is ${size.$1}x${size.$2}, expected '
        '${expected.$1}x${expected.$2}',
      );
    } else {
      _ok('$name ${size.$1}x${size.$2}');
    }
  }
}

/// Width/height straight out of the PNG header, without decoding the image.
(int, int) _ihdrSize(File file) {
  final bytes = file.openSync().readSync(33);
  final signature = [137, 80, 78, 71, 13, 10, 26, 10];
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) throw StateError('${file.path} is not a PNG');
  }
  int be32(int at) =>
      (bytes[at] << 24) |
      (bytes[at + 1] << 16) |
      (bytes[at + 2] << 8) |
      bytes[at + 3];
  return (be32(16), be32(20));
}

void _checkCapture(File file) {
  final name = p.basename(file.path);
  final image = img.decodePng(file.readAsBytesSync());
  if (image == null) {
    _fail('$name could not be decoded');
    return;
  }

  final isTablet = name.startsWith('tab-');
  if (isTablet) {
    if (image.width != _tabletCapture.$1 || image.height != _tabletCapture.$2) {
      _fail(
        '$name is ${image.width}x${image.height}, expected '
        '${_tabletCapture.$1}x${_tabletCapture.$2}',
      );
    }
  } else if (image.width != _phoneCaptureWidth) {
    _fail('$name is ${image.width}px wide, expected $_phoneCaptureWidth');
  }

  final edges = <String, int>{
    'top': _rowTransitions(image, 0),
    'bottom': _rowTransitions(image, image.height - 1),
    'left': _columnTransitions(image, 0),
    'right': _columnTransitions(image, image.width - 1),
  };
  final busy = edges.entries
      .where((e) => e.value > _maxEdgeTransitions)
      .map((e) => '${e.key}=${e.value}')
      .toList();
  if (busy.isNotEmpty) {
    _fail(
      '$name has content cut by an edge (transitions: '
      '${busy.join(', ')}, limit $_maxEdgeTransitions)',
    );
  } else {
    _ok(
      '$name ${image.width}x${image.height}, edges flat '
      '(${edges.values.join('/')})',
    );
  }
}

int _rowTransitions(img.Image image, int y) =>
    _transitions([for (var x = 0; x < image.width; x++) image.getPixel(x, y)]);

int _columnTransitions(img.Image image, int x) =>
    _transitions([for (var y = 0; y < image.height; y++) image.getPixel(x, y)]);

int _transitions(List<img.Pixel> line) {
  var count = 0;
  for (var i = 1; i < line.length; i++) {
    final a = line[i - 1];
    final b = line[i];
    final delta = (a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs();
    if (delta > _transitionThreshold) count++;
  }
  return count;
}
