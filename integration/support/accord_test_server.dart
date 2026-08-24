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
///  4. `ACCORD_SERVER_IMAGE` (default is the reviewed digest below)
///     run under docker.
///
/// If none resolve, [AccordTestServer.start] throws [ServerUnavailable]; call
/// it through [describeOrSkip] to turn that into a skipped suite with an
/// explanatory message rather than a wall of failures.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _defaultImage =
    'ghcr.io/daccordproject/accordserver@sha256:9f76756599fded6ec3f8b5f9638ed436e3ff73b96df24afd880c40673da8acf2';
const _defaultLiveKitImage =
    'livekit/livekit-server@sha256:9e34703b97ceb9f622bcbb533107e4786c7aa65966f0494966a452ad41a0c0d4';

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
    _LiveKitFixture? liveKit,
  }) : _process = process,
       _containerName = containerName,
       _dataDir = dataDir,
       _liveKit = liveKit;

  /// e.g. `http://127.0.0.1:41234` — no trailing slash, no `/api/v1`.
  final String baseUrl;
  final ServerSource source;

  final Process? _process;
  final String? _containerName;
  final Directory? _dataDir;
  final _LiveKitFixture? _liveKit;

  /// Whether this run was explicitly configured with a real LiveKit SFU.
  bool get hasLiveKit =>
      _liveKit != null || source == ServerSource.external && liveKitRequested;
  bool get managesLiveKit => _liveKit != null;

  /// The heavy media fixture is opt-in so normal protocol/controller runs stay
  /// cheap and do not depend on Docker, UDP, audio devices, or WebRTC.
  static bool get liveKitRequested => _env('ACCORD_TEST_LIVEKIT') == '1';

  /// The gateway URL matching [baseUrl].
  String get gatewayUrl => '${baseUrl.replaceFirst(RegExp(r'^http'), 'ws')}/ws';

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
      final candidate = File(
        '../accordserver/target/$profile/accordserver',
      ).absolute;
      if (candidate.existsSync()) return candidate.path;
    }
    return null;
  }

  static Future<AccordTestServer> _startBinary(String binary) async {
    final port = await _freePort();
    final dataDir = Directory.systemTemp.createTempSync(
      'accord-integration-test-',
    );

    final liveKit = liveKitRequested ? await _LiveKitFixture.start() : null;

    late final Process process;
    try {
      process = await Process.start(
        binary,
        const [],
        environment: _serverEnvironment(
          port: port,
          databaseUrl: 'sqlite:${dataDir.path}/accord.db?mode=rwc',
          storagePath: '${dataDir.path}/cdn',
          liveKit: liveKit,
        ),
      );
    } on Object {
      await liveKit?.stop();
      rethrow;
    }

    final logs = _captureLogs(process);
    final url = 'http://127.0.0.1:$port';

    if (!await _waitForHealth(url, const Duration(seconds: 30))) {
      process.kill(ProcessSignal.sigkill);
      dataDir.deleteSync(recursive: true);
      await liveKit?.stop();
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
      liveKit: liveKit,
    );
  }

  static Future<AccordTestServer> _startDocker() async {
    final port = await _freePort();
    final image = _env('ACCORD_SERVER_IMAGE') ?? _defaultImage;
    final name = 'accord-integration-test-$port';
    final liveKit = liveKitRequested ? await _LiveKitFixture.start() : null;

    final environment = _serverEnvironment(
      port: port,
      databaseUrl: 'sqlite:data/accord.db?mode=rwc',
      storagePath: '/app/data/cdn',
      liveKit: liveKit,
    );

    final result = await Process.run('docker', [
      'run',
      '--detach',
      '--rm',
      '--name',
      name,
      if (liveKit != null) ...[
        '--network',
        'host',
      ] else ...[
        '--publish',
        '127.0.0.1:$port:$port',
      ],
      for (final entry in environment.entries) ...[
        '--env',
        '${entry.key}=${entry.value}',
      ],
      if (liveKit == null) ...['--env', 'ACCORD_BIND=0.0.0.0'],
      image,
    ]);

    if (result.exitCode != 0) {
      await liveKit?.stop();
      throw ServerUnavailable('docker run $image failed:\n${result.stderr}');
    }

    final url = 'http://127.0.0.1:$port';
    if (!await _waitForHealth(url, const Duration(seconds: 60))) {
      final logs = await Process.run('docker', ['logs', name]);
      await Process.run('docker', ['kill', name]);
      await liveKit?.stop();
      throw ServerUnavailable(
        'accordserver container did not become healthy on $url.\n'
        '--- container output ---\n${logs.stdout}${logs.stderr}',
      );
    }

    return AccordTestServer._(
      baseUrl: url,
      source: ServerSource.docker,
      containerName: name,
      liveKit: liveKit,
    );
  }

  static Map<String, String> _serverEnvironment({
    required int port,
    required String databaseUrl,
    required String storagePath,
    required _LiveKitFixture? liveKit,
  }) => {
    'PORT': '$port',
    'ACCORD_BIND': '127.0.0.1',
    'DATABASE_URL': databaseUrl,
    'ACCORD_STORAGE_PATH': storagePath,
    if (liveKit == null) 'ACCORD_TEST_MODE': '1',
    'LIVEKIT_URL': liveKit?.internalUrl ?? 'ws://127.0.0.1:7880',
    'LIVEKIT_EXTERNAL_URL': liveKit?.externalUrl ?? 'ws://127.0.0.1:7880',
    'LIVEKIT_API_KEY': 'devkey',
    'LIVEKIT_API_SECRET': 'secret',
    'RUST_LOG': _env('ACCORD_TEST_LOG') ?? 'warn',
  };

  /// Interrupts the opt-in SFU without changing its ports. The real-client
  /// scenario uses this to drive LiveKit into a terminal dropped state, then
  /// verifies a fresh `voice.server_update` reconnects the existing session.
  Future<void> stopLiveKit() async {
    final liveKit = _liveKit;
    if (liveKit == null) {
      throw StateError('This AccordTestServer has no managed LiveKit fixture.');
    }
    await liveKit.stop();
  }

  Future<void> restartLiveKit() async {
    final liveKit = _liveKit;
    if (liveKit == null) {
      throw StateError('This AccordTestServer has no managed LiveKit fixture.');
    }
    await liveKit.restart();
  }

  /// LiveKit's development-only debug endpoint is adequate for the test
  /// fixture and avoids adding a production RoomService/JWT dependency.
  Future<bool> liveKitRoomExists(String roomName) async {
    final liveKit = _liveKit;
    if (liveKit == null) return false;
    final client = HttpClient();
    try {
      final request = await client.getUrl(
        Uri.parse('${liveKit.httpUrl}/debug/rooms'),
      );
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      return response.statusCode == 200 && body.contains(roomName);
    } finally {
      client.close(force: true);
    }
  }

  Future<String> liveKitLogs() async {
    final liveKit = _liveKit;
    return liveKit == null ? '' : liveKit.logs();
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
    await _liveKit?.stop();
  }

  static Future<bool> _dockerAvailable() async {
    try {
      final result = await Process.run('docker', [
        'info',
        '--format',
        '{{.ID}}',
      ]);
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

  static Future<bool> _waitForHealth(
    String baseUrl,
    Duration timeout, {
    String path = '/health',
  }) async {
    final deadline = DateTime.now().add(timeout);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      while (DateTime.now().isBefore(deadline)) {
        try {
          final request = await client.getUrl(Uri.parse('$baseUrl$path'));
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

class _LiveKitFixture {
  _LiveKitFixture({
    required this.containerName,
    required this.image,
    required this.signalPort,
    required this.tcpPort,
    required this.udpPort,
  });

  final String containerName;
  final String image;
  final int signalPort;
  final int tcpPort;
  final int udpPort;

  String get httpUrl => 'http://127.0.0.1:$signalPort';
  String get internalUrl => httpUrl;
  String get externalUrl => 'ws://127.0.0.1:$signalPort';

  static Future<_LiveKitFixture> start() async {
    if (!await AccordTestServer._dockerAvailable()) {
      throw ServerUnavailable(
        'ACCORD_TEST_LIVEKIT=1 requires a working Docker daemon to run the '
        'digest-pinned LiveKit fixture.',
      );
    }
    final tcpPorts = await _freeTcpPorts(2);
    final udpPort = await _freeUdpPort();
    final fixture = _LiveKitFixture(
      containerName: 'accord-livekit-test-${tcpPorts.first}',
      image:
          AccordTestServer._env('ACCORD_TEST_LIVEKIT_IMAGE') ??
          _defaultLiveKitImage,
      signalPort: tcpPorts[0],
      tcpPort: tcpPorts[1],
      udpPort: udpPort,
    );
    await fixture.restart();
    return fixture;
  }

  Future<void> restart() async {
    await _removeContainer();
    final result = await Process.run('docker', [
      'run',
      '--detach',
      '--name', containerName,
      // Linux host networking gives both the desktop WebRTC client and a
      // containerized accordserver the same loopback endpoint and advertised
      // ICE candidates. This fixture is intentionally Linux-only in CI.
      '--network', 'host',
      image,
      '--dev',
      '--bind', '127.0.0.1',
      '--node-ip', '127.0.0.1',
      '--port', '$signalPort',
      '--rtc.tcp_port', '$tcpPort',
      '--udp-port', '$udpPort',
      '--keys', 'devkey: secret',
    ]);
    if (result.exitCode != 0) {
      throw ServerUnavailable(
        'LiveKit fixture $image failed to start:\n${result.stderr}',
      );
    }
    if (!await AccordTestServer._waitForHealth(
      httpUrl,
      const Duration(seconds: 30),
      path: '/',
    )) {
      final logs = await Process.run('docker', ['logs', containerName]);
      await stop();
      throw ServerUnavailable(
        'LiveKit fixture did not become healthy on $httpUrl.\n'
        '--- container output ---\n${logs.stdout}${logs.stderr}',
      );
    }
  }

  Future<void> stop() async {
    await _removeContainer();
  }

  Future<String> logs() async {
    final result = await Process.run('docker', ['logs', containerName]);
    return '${result.stdout}${result.stderr}';
  }

  Future<void> _removeContainer() async {
    await Process.run('docker', ['rm', '--force', containerName]);
  }

  static Future<List<int>> _freeTcpPorts(int count) async {
    final sockets = <ServerSocket>[];
    try {
      for (var i = 0; i < count; i++) {
        sockets.add(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0));
      }
      return [for (final socket in sockets) socket.port];
    } finally {
      for (final socket in sockets) {
        await socket.close();
      }
    }
  }

  static Future<int> _freeUdpPort() async {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final port = socket.port;
    socket.close();
    return port;
  }
}
