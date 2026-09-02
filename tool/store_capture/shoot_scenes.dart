// Photographs the capture app's six scenes with a headless Chromium and writes
// them to the tablet capture set.
//
// Driven by `store-media/ios-generator/capture-inner.sh`, which starts the
// server this points at. Run it directly only if that server is already up:
//
//     dart run tool/store_capture/shoot_scenes.dart \
//       --chrome /usr/bin/chromium --url http://localhost:8099 \
//       --out store-media/ios-generator/inner
//
// Why the DevTools protocol rather than `chromium --screenshot`, the way
// `render.sh` does it: the CLI screenshot fires on the load event, and
// `--virtual-time-budget` does not wait for a Flutter app's first frame (the
// engine boots off `requestAnimationFrame`, and virtual time runs out with the
// splash still up). CDP lets us navigate, wait for real time to pass, and only
// then capture.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// The capture canvas, in CSS pixels: a 13" iPad in landscape.
///
/// Landscape is the point of this set — the home screen only puts all four
/// panes (rail, channel list, message column, member roster) on screen above
/// `kHomeMemberListBreakpoint`, and a portrait iPad sits below it.
const _width = 1366;
const _height = 1024;

/// 1366x1024 CSS px at 2x = the 2732x2048 the device frame expects.
const _scale = 2;

/// Scene number -> file name in the capture set.
const _scenes = {
  1: 'tab-01',
  2: 'tab-02',
  3: 'tab-03',
  4: 'tab-04',
  5: 'tab-05',
  6: 'tab-06',
};

Future<void> main(List<String> args) async {
  final options = _parseArgs(args);
  final chrome = options['chrome'];
  final base = options['url'] ?? 'http://localhost:8099';
  final outDir = options['out'] ?? 'store-media/ios-generator/inner';
  final settle = Duration(milliseconds: int.parse(options['wait'] ?? '18000'));
  if (chrome == null) {
    stderr.writeln(
      'usage: shoot_scenes.dart --chrome <path> [--url <base>] '
      '[--out <dir>] [--wait <ms>]',
    );
    exit(64);
  }

  final profile = Directory.systemTemp.createTempSync('store-capture-chrome-');
  final process = await Process.start(chrome, [
    '--headless=new',
    '--no-sandbox',
    '--disable-dev-shm-usage',
    // Headless has no GPU here; SwiftShader is what rasterises the app's WebGL
    // canvas. Without opting in, Chromium refuses the software fallback.
    '--enable-unsafe-swiftshader',
    '--hide-scrollbars',
    '--remote-debugging-port=0',
    '--user-data-dir=${profile.path}',
    'about:blank',
  ]);
  final endpoint = Completer<String>();
  process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(
    (line) {
      final match = RegExp(r'ws://\S+').firstMatch(line);
      if (match != null && !endpoint.isCompleted) {
        endpoint.complete(match.group(0));
      }
    },
  );

  final browser = await _Cdp.connect(
    await endpoint.future.timeout(const Duration(seconds: 30)),
  );
  try {
    final target = await browser.send('Target.createTarget', {
      'url': 'about:blank',
    });
    final attach = await browser.send('Target.attachToTarget', {
      'targetId': target['targetId'],
      'flatten': true,
    });
    final session = attach['sessionId'] as String;

    await browser.send('Emulation.setDeviceMetricsOverride', {
      'width': _width,
      'height': _height,
      'deviceScaleFactor': _scale,
      'mobile': false,
    }, session: session);
    await browser.send('Page.enable', const {}, session: session);

    Directory(outDir).createSync(recursive: true);
    for (final entry in _scenes.entries) {
      await browser.send('Page.navigate', {
        'url': '$base/?scene=${entry.key}',
      }, session: session);
      // Real time, not virtual: the app has to boot, run its seeded REST reads
      // and settle before it is worth photographing.
      await Future<void>.delayed(settle);
      final shot = await browser.send('Page.captureScreenshot', {
        'format': 'png',
      }, session: session);
      final file = File(p.join(outDir, '${entry.value}.png'));
      file.writeAsBytesSync(base64Decode(shot['data'] as String));
      stdout.writeln('wrote ${file.path}');
    }
  } finally {
    browser.close();
    process.kill();
    try {
      profile.deleteSync(recursive: true);
    } on FileSystemException {
      // A browser still shutting down may hold files; the temp dir is
      // disposable either way.
    }
  }
}

Map<String, String> _parseArgs(List<String> args) {
  final options = <String, String>{};
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i].startsWith('--')) options[args[i].substring(2)] = args[i + 1];
  }
  return options;
}

/// The slice of the Chrome DevTools Protocol this needs: send a command, await
/// its reply, optionally within an attached session.
class _Cdp {
  _Cdp(this._socket) {
    _socket.listen((raw) {
      final message = jsonDecode(raw as String) as Map<String, dynamic>;
      final id = message['id'];
      if (id is! int) return; // an event, not a command reply
      final pending = _pending.remove(id);
      if (pending == null) return;
      final error = message['error'];
      if (error != null) {
        pending.completeError(StateError('CDP error: $error'));
      } else {
        pending.complete((message['result'] as Map).cast<String, dynamic>());
      }
    });
  }

  static Future<_Cdp> connect(String url) async =>
      _Cdp(await WebSocket.connect(url));

  final WebSocket _socket;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  var _nextId = 1;

  Future<Map<String, dynamic>> send(
    String method,
    Map<String, dynamic> params, {
    String? session,
  }) {
    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    _socket.add(
      jsonEncode({
        'id': id,
        'method': method,
        'params': params,
        if (session != null) 'sessionId': session,
      }),
    );
    return completer.future.timeout(const Duration(seconds: 120));
  }

  void close() => _socket.close();
}
