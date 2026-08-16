/// Boots a real `accordserver` for the integration suite and tears it down
/// again, so tests can drive [AccordClient] against actual REST + gateway
/// traffic instead of mocks.
///
/// Resolution order (first one that works wins):
///
///  1. `ACCORD_TEST_SERVER_URL` — an already-running server. Nothing is
///     spawned and nothing is torn down; useful for pointing the suite at a
///     staging box or a server you're debugging under a profiler.
///  2. `ACCORD_SERVER_BIN` — an explicit path to an `accordserver` binary.
///  3. An auto-detected binary from a sibling checkout, i.e.
///     `../accordserver/target/{release,debug}/accordserver`.
///  4. `ACCORD_SERVER_IMAGE` (default `ghcr.io/daccordproject/accordserver:latest`)
///     run under docker.
///
/// If none resolve, [AccordTestServer.start] throws [ServerUnavailable]; call
/// it through [describeOrSkip] to turn that into a skipped suite with an
/// explanatory message rather than a wall of failures.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _defaultImage = 'ghcr.io/daccordproject/accordserver:latest';

/// Thrown when no server could be resolved from the environment.
class ServerUnavailable implements Exception {
  ServerUnavailable(this.message);

  final String message;

  @override
  String toString() => 'ServerUnavailable: $message';
}

/// How a given [AccordTestServer] was obtained.
enum ServerSource { external, binary, docker }

/// A running Accord server the tests can talk to.
class AccordTestServer {
  AccordTestServer._({
    required this.baseUrl,
    required this.source,
    Process? process,
    String? containerName,
    Directory? dataDir,
  })  : _process = process,
        _containerName = containerName,
        _dataDir = dataDir;

  /// e.g. `http://127.0.0.1:41234` — no trailing slash, no `/api/v1`.
  final String baseUrl;
  final ServerSource source;

  final Process? _process;
  final String? _containerName;
  final Directory? _dataDir;

  /// The gateway URL matching [baseUrl].
  String get gatewayUrl =>
      '${baseUrl.replaceFirst(RegExp(r'^http'), 'ws')}/ws';

  /// Registrations are rate-limited per IP by the server (5 per 15 minutes,
  /// see `check_register_rate_limit` in accordserver's `src/routes/auth.rs`),
  /// and `ACCORD_TEST_MODE` does not bypass it. We track usage so exhausting
  /// the budget produces a clear message instead of an opaque 429.
  int registrationsUsed = 0;
  static const int registrationBudget = 5;

  static Future<AccordTestServer> start() async {
    final external = _env('ACCORD_TEST_SERVER_URL');
    if (external != null) {
      final url = external.replaceAll(RegExp(r'/+$'), '');
      if (!await _waitForHealth(url, const Duration(seconds: 5))) {
        throw ServerUnavailable(
          'ACCORD_TEST_SERVER_URL is set to $url but /health did not respond.',
        );
      }
      return AccordTestServer._(baseUrl: url, source: ServerSource.external);
    }

    final binary = _resolveBinary();
    if (binary != null) return _startBinary(binary);

    if (await _dockerAvailable()) return _startDocker();

    throw ServerUnavailable(
      'No accordserver available. Provide one of:\n'
      '  ACCORD_TEST_SERVER_URL=http://host:port   (use a running server)\n'
      '  ACCORD_SERVER_BIN=/path/to/accordserver   (spawn a local build)\n'
      '  a sibling checkout built at ../accordserver/target/{release,debug}\n'
      '  docker, to run $_defaultImage',
    );
  }

  static String? _resolveBinary() {
    final explicit = _env('ACCORD_SERVER_BIN');
    if (explicit != null) {
      if (File(explicit).existsSync()) return explicit;
      throw ServerUnavailable('ACCORD_SERVER_BIN=$explicit does not exist.');
    }

    // Sibling checkout, relative to this repo's root (the test CWD).
    for (final profile in const ['release', 'debug']) {
      final candidate =
          File('../accordserver/target/$profile/accordserver').absolute;
      if (candidate.existsSync()) return candidate.path;
    }
    return null;
  }

  static Future<AccordTestServer> _startBinary(String binary) async {
    final port = await _freePort();
    final dataDir =
        Directory.systemTemp.createTempSync('accord-integration-test-');

    final process = await Process.start(
      binary,
      const [],
      environment: {
        'PORT': '$port',
        'ACCORD_BIND': '127.0.0.1',
        'DATABASE_URL': 'sqlite:${dataDir.path}/accord.db?mode=rwc',
        'ACCORD_STORAGE_PATH': '${dataDir.path}/cdn',
        // Relaxes the LiveKit requirement so voice-state paths are reachable
        // without a real SFU. It does NOT relax auth or rate limits.
        'ACCORD_TEST_MODE': '1',
        // Voice endpoints 400 with "voice_not_configured" unless a LiveKit
        // client is configured, even in test mode. Test mode skips actually
        // talking to the SFU (no room creation, no participant cleanup) but
        // still mints a token and broadcasts voice.state_update — which is
        // what makes voice-state fan-out testable without running one. The
        // URL is never dialled by the server.
        'LIVEKIT_URL': 'ws://127.0.0.1:7880',
        'LIVEKIT_EXTERNAL_URL': 'ws://127.0.0.1:7880',
        'LIVEKIT_API_KEY': 'devkey',
        'LIVEKIT_API_SECRET': 'secret',
        'RUST_LOG': _env('ACCORD_TEST_LOG') ?? 'warn',
      },
    );

    final logs = _captureLogs(process);
    final url = 'http://127.0.0.1:$port';

    if (!await _waitForHealth(url, const Duration(seconds: 30))) {
      process.kill(ProcessSignal.sigkill);
      dataDir.deleteSync(recursive: true);
      throw ServerUnavailable(
        'accordserver ($binary) did not become healthy on $url.\n'
        '--- server output ---\n${logs.toString()}',
      );
    }

    return AccordTestServer._(
      baseUrl: url,
      source: ServerSource.binary,
      process: process,
      dataDir: dataDir,
    );
  }

  static Future<AccordTestServer> _startDocker() async {
    final port = await _freePort();
    final image = _env('ACCORD_SERVER_IMAGE') ?? _defaultImage;
    final name = 'accord-integration-test-$port';

    final result = await Process.run('docker', [
      'run',
      '--detach',
      '--rm',
      '--name', name,
      '--publish', '127.0.0.1:$port:$port',
      '--env', 'PORT=$port',
      '--env', 'ACCORD_BIND=0.0.0.0',
      '--env', 'DATABASE_URL=sqlite:data/accord.db?mode=rwc',
      '--env', 'ACCORD_STORAGE_PATH=/app/data/cdn',
      '--env', 'ACCORD_TEST_MODE=1',
      // See the binary path above: configured, never dialled.
      '--env', 'LIVEKIT_URL=ws://127.0.0.1:7880',
      '--env', 'LIVEKIT_EXTERNAL_URL=ws://127.0.0.1:7880',
      '--env', 'LIVEKIT_API_KEY=devkey',
      '--env', 'LIVEKIT_API_SECRET=secret',
      '--env', 'RUST_LOG=${_env('ACCORD_TEST_LOG') ?? 'warn'}',
      image,
    ]);

    if (result.exitCode != 0) {
      throw ServerUnavailable(
        'docker run $image failed:\n${result.stderr}',
      );
    }

    final url = 'http://127.0.0.1:$port';
    if (!await _waitForHealth(url, const Duration(seconds: 60))) {
      final logs = await Process.run('docker', ['logs', name]);
      await Process.run('docker', ['kill', name]);
      throw ServerUnavailable(
        'accordserver container did not become healthy on $url.\n'
        '--- container output ---\n${logs.stdout}${logs.stderr}',
      );
    }

    return AccordTestServer._(
      baseUrl: url,
      source: ServerSource.docker,
      containerName: name,
    );
  }

  /// Stops the server and removes its scratch data. Safe to call twice, and a
  /// no-op for [ServerSource.external].
  Future<void> stop() async {
    switch (source) {
      case ServerSource.external:
        return;
      case ServerSource.binary:
        final process = _process;
        if (process != null) {
          process.kill(ProcessSignal.sigterm);
          await process.exitCode.timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              process.kill(ProcessSignal.sigkill);
              return -1;
            },
          );
        }
        if (_dataDir != null && _dataDir.existsSync()) {
          _dataDir.deleteSync(recursive: true);
        }
      case ServerSource.docker:
        await Process.run('docker', ['kill', _containerName!]);
    }
  }

  static Future<bool> _dockerAvailable() async {
    try {
      final result = await Process.run('docker', ['info', '--format', '{{.ID}}']);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  static Future<int> _freePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  static Future<bool> _waitForHealth(String baseUrl, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      while (DateTime.now().isBefore(deadline)) {
        try {
          final request = await client.getUrl(Uri.parse('$baseUrl/health'));
          final response = await request.close();
          await response.drain<void>();
          if (response.statusCode == 200) return true;
        } on Object {
          // Not up yet — keep polling until the deadline.
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// Buffers a spawned server's output so a failed boot can report why.
  static StringBuffer _captureLogs(Process process) {
    final buffer = StringBuffer();
    void sink(Stream<List<int>> stream) {
      stream.transform(utf8.decoder).listen(buffer.write, onError: (_) {});
    }

    sink(process.stdout);
    sink(process.stderr);
    return buffer;
  }

  static String? _env(String key) {
    final value = Platform.environment[key];
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }
}
