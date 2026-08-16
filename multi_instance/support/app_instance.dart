/// Launches real Daccord app processes and drives them through the MCP server
/// the app already exposes in Developer Mode.
///
/// This is how layer 3 (#222) sees both sides of an interaction: two actual
/// clients, each with its own storage and gateway connection, talking to one
/// server. No synthetic input — every action goes through the same JSON-RPC
/// tool surface a developer or an agent would use (`mcp_tools.dart`).
///
/// Each instance gets a throwaway `HOME`, so instances can't collide over Hive
/// boxes and none of them can touch your real profile data. Settings and the
/// session are seeded before launch, which is what makes the app come up
/// already signed in with its MCP server listening.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bonfire/features/profiles/services/profile_store.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:hive_ce/hive.dart';

import '../../integration/support/harness.dart';

/// Thrown when no app bundle is available to launch.
class AppUnavailable implements Exception {
  AppUnavailable(this.message);

  final String message;

  @override
  String toString() => 'AppUnavailable: $message';
}

/// One running app process, addressable over its MCP port.
class AppInstance {
  AppInstance._({
    required this.label,
    required this.port,
    required this.account,
    required Directory home,
    required Process process,
  })  : _home = home,
        _process = process;

  /// Human-readable name used in failure messages ("alice", "bob").
  final String label;

  /// Loopback port this instance's MCP server is listening on.
  final int port;

  final TestAccount account;

  final Directory _home;
  final Process _process;
  final HttpClient _http = HttpClient();
  final StringBuffer _log = StringBuffer();

  /// Everything the process wrote to stdout/stderr, for failure messages.
  String get log => _log.toString();

  // ── Driving ───────────────────────────────────────────────────────────────

  /// Calls an MCP tool and returns the tool's own result map.
  ///
  /// The transport wraps results twice — JSON-RPC `result.content[0].text`
  /// holds the tool's JSON as a string — so this unwraps both layers and
  /// surfaces a tool-level `error` as a thrown [StateError], since every call
  /// site treats one as a failure.
  Future<Map<String, dynamic>> call(
    String tool, [
    Map<String, dynamic> arguments = const {},
  ]) async {
    final response = await _rpc({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'tools/call',
      'params': {'name': tool, 'arguments': arguments},
    });

    final error = response['error'];
    if (error != null) {
      throw StateError('$label: MCP call $tool failed: $error');
    }

    final content = (response['result'] as Map)['content'] as List;
    final decoded =
        jsonDecode((content.first as Map)['text'] as String) as Map;
    final result = Map<String, dynamic>.from(decoded);
    if (result['error'] != null) {
      throw StateError('$label: tool $tool returned ${result['error']}');
    }
    return result;
  }

  /// Polls [call] until [until] holds.
  ///
  /// Anything crossing the gateway takes time to arrive, and a bare call would
  /// assert against whatever happened to be true in the first millisecond.
  Future<Map<String, dynamic>> callUntil(
    String tool,
    bool Function(Map<String, dynamic> result) until, {
    Map<String, dynamic> arguments = const {},
    Duration timeout = const Duration(seconds: 20),
    Duration interval = const Duration(milliseconds: 250),
    String? description,
  }) async {
    final deadline = DateTime.now().add(timeout);
    Map<String, dynamic>? last;
    while (DateTime.now().isBefore(deadline)) {
      last = await call(tool, arguments);
      if (until(last)) return last;
      await Future<void>.delayed(interval);
    }
    throw TimeoutException(
      '$label: ${description ?? tool} never satisfied within $timeout '
      '(last result: $last)',
    );
  }

  Future<Map<String, dynamic>> _rpc(Map<String, dynamic> body) async {
    // One retry, because a keep-alive socket can be closed by the app between
    // our reuse of it and the request landing — "Connection closed before full
    // header was received". `persistentConnection: false` below makes that
    // rare; the retry covers the rest rather than failing a test over a
    // transport hiccup that says nothing about the app.
    for (var attempt = 0;; attempt++) {
      try {
        return await _rpcOnce(body);
      } on HttpException {
        if (attempt >= 1) rethrow;
      } on SocketException {
        if (attempt >= 1) rethrow;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<Map<String, dynamic>> _rpcOnce(Map<String, dynamic> body) async {
    final request =
        await _http.postUrl(Uri.parse('http://127.0.0.1:$port/mcp'));
    // Each call gets its own connection: the driver is chatty and long-lived,
    // and a pooled socket that the app has since dropped fails the next call.
    request.persistentConnection = false;
    request.headers.contentType = ContentType.json;
    request.add(utf8.encode(jsonEncode(body)));
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw StateError('$label: MCP HTTP ${response.statusCode}: $text');
    }
    return Map<String, dynamic>.from(jsonDecode(text) as Map);
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Seeds a throwaway profile for [account], launches the app against it, and
  /// waits for the MCP server to answer.
  static Future<AppInstance> launch({
    required TestAccount account,
    required String label,
    required int port,
  }) async {
    final binary = resolveBinary();
    final home =
        Directory.systemTemp.createTempSync('accord-instance-$label-');
    prepareHome(home);
    await seedProfile(home: home, account: account, port: port);

    final process = await Process.start(
      binary,
      const [],
      environment: {
        // Everything the app resolves through path_provider hangs off these,
        // so they're what actually isolates one instance from another — and
        // from your real profile.
        'HOME': home.path,
        // Not what path_provider reads (see documentsDirFor), but keep it
        // consistent for anything else that honours it.
        'XDG_DOCUMENTS_DIR': documentsDirFor(home),
        'XDG_DATA_HOME': '${home.path}/.local/share',
        'XDG_CONFIG_HOME': '${home.path}/.config',
        'XDG_CACHE_HOME': '${home.path}/.cache',
        // Under xvfb there's no DRI device ("libEGL warning: DRI3 error"),
        // and the app can't get a GL context, so it never reaches a first
        // frame — and the MCP server only starts once the widget tree builds.
        // llvmpipe is slower but always available.
        'LIBGL_ALWAYS_SOFTWARE': '1',
        // Silences "Atk-CRITICAL atk_socket_embed" spam on headless runners,
        // where there's no accessibility bus to embed into.
        'NO_AT_BRIDGE': '1',
        if (Platform.environment['DISPLAY'] != null)
          'DISPLAY': Platform.environment['DISPLAY']!,
        if (Platform.environment['WAYLAND_DISPLAY'] != null)
          'WAYLAND_DISPLAY': Platform.environment['WAYLAND_DISPLAY']!,
        if (Platform.environment['XAUTHORITY'] != null)
          'XAUTHORITY': Platform.environment['XAUTHORITY']!,
      },
    );

    final instance = AppInstance._(
      label: label,
      port: port,
      account: account,
      home: home,
      process: process,
    );
    instance._captureOutput();

    // Generous because a headless runner on llvmpipe is far slower to a first
    // frame than a desktop with a GPU, and the MCP server doesn't exist until
    // the widget tree builds.
    if (!await instance._waitForMcp(const Duration(seconds: 150))) {
      final log = instance.log;
      await instance.dispose();
      throw AppUnavailable(
        "$label: the app's MCP server never answered on port $port.\n"
        '--- app output ---\n$log',
      );
    }
    return instance;
  }

  /// The app bundle to launch: `DACCORD_APP_BIN`, else a local release build,
  /// else debug.
  ///
  /// Release first on purpose. A *debug* bundle launched directly never runs
  /// its Dart entrypoint — the engine starts, native plugins register and the
  /// GTK loop idles, but `main()` never executes, so no Hive box is ever
  /// opened and the MCP server never starts. It presents as a window that
  /// simply does nothing. `flutter test -d linux` drives debug bundles fine
  /// because the tool attaches and injects the entrypoint; nothing does that
  /// here.
  static String resolveBinary() {
    final explicit = Platform.environment['DACCORD_APP_BIN'];
    if (explicit != null && explicit.trim().isNotEmpty) {
      if (File(explicit).existsSync()) return explicit;
      throw AppUnavailable('DACCORD_APP_BIN=$explicit does not exist.');
    }
    for (final mode in const ['release', 'debug']) {
      final candidate = File('build/linux/x64/$mode/bundle/daccord').absolute;
      if (candidate.existsSync()) return candidate.path;
    }
    throw AppUnavailable(
      'No Daccord app bundle found. Build one first:\n'
      '  flutter build linux --release\n'
      'or point DACCORD_APP_BIN at an existing bundle.',
    );
  }

  /// Where the app will put its data for an instance rooted at [home].
  ///
  /// Resolved the same way the app resolves it, rather than assumed: Flutter's
  /// `getApplicationDocumentsDirectory()` on Linux calls
  /// `xdg.getUserDirectory('DOCUMENTS')`, which shells out to the
  /// `xdg-user-dir` **executable** and ignores `XDG_DOCUMENTS_DIR` entirely.
  /// Under a fresh HOME with no `user-dirs.dirs`, that returns `$HOME` itself,
  /// not `$HOME/Documents` — so seeding the obvious path silently writes
  /// somewhere the app never reads, and the app comes up with default settings
  /// and no MCP server. [prepareHome] writes a `user-dirs.dirs` to make this
  /// deterministic; this asks the same question the app will.
  static String documentsDirFor(Directory home) {
    try {
      final result = Process.runSync(
        'xdg-user-dir',
        ['DOCUMENTS'],
        environment: {'HOME': home.path},
        includeParentEnvironment: true,
      );
      final path = (result.stdout as String).split('\n').first.trim();
      if (path.isNotEmpty) return path;
    } on ProcessException {
      // xdg-user-dir isn't installed; fall through.
    }
    return '${home.path}/Documents';
  }

  /// Gives an instance home the XDG layout `xdg-user-dir` needs to resolve
  /// DOCUMENTS inside it.
  static void prepareHome(Directory home) {
    Directory('${home.path}/.config').createSync(recursive: true);
    File('${home.path}/.config/user-dirs.dirs')
        .writeAsStringSync('XDG_DOCUMENTS_DIR="\$HOME/Documents"\n');
    Directory('${home.path}/Documents').createSync(recursive: true);
    // Fontconfig warns loudly on every launch without a writable cache dir.
    Directory('${home.path}/.cache/fontconfig').createSync(recursive: true);
  }

  /// Writes the settings and session boxes the app reads at startup.
  ///
  /// Hive's home path is process-global, so this initialises, writes and closes
  /// one instance's storage before the next is seeded. Fine here because
  /// seeding always happens before any app is launched.
  @visibleForTesting
  static Future<void> seedProfile({
    required Directory home,
    required TestAccount account,
    required int port,
  }) async {
    final dataDir = Directory('${documentsDirFor(home)}/daccord/data')
      ..createSync(recursive: true);

    Hive.init(dataDir.path);
    // The default profile keeps its boxes at the root data dir (see
    // ProfileStore), so writing them here is what the app will read.
    final settings = await Hive.openBox(ProfileStore.settingsBoxName);
    await settings.put('settings', <String, dynamic>{
      // Developer Mode + MCP are both required before the server runs, and the
      // default allowed groups are read/navigate only — the rest have to be
      // asked for explicitly or every other tool 404s.
      'developerMode': true,
      'mcpEnabled': true,
      'mcpPort': port,
      'mcpToken': '',
      'mcpAllowedGroups': AccordSettings.mcpToolGroups,
      // Same first-launch suppressions the other layers need: dialogs would
      // sit on top of the UI, and the updater would stage a real download.
      'notificationsEnabled': false,
      'autoUpdateCheck': false,
      'errorReportingConsentShown': true,
      'soundsEnabled': false,
    });
    await settings.put('onboarding-seen-version', '99.0.0');
    await settings.put('release-notes-seen-version', '99.0.0');

    // Persisting a session is what makes the app come up signed in: the login
    // screen restores it on its first frame.
    final session = await Hive.openBox(ProfileStore.sessionBoxName);
    final json = account.session.toJson();
    await session.put('session', json);
    await session.put('accounts', [json]);

    await Hive.close();
  }

  void _captureOutput() {
    void sink(Stream<List<int>> stream) {
      stream.transform(utf8.decoder).listen(_log.write, onError: (_) {});
    }

    sink(_process.stdout);
    sink(_process.stderr);
  }

  Future<bool> _waitForMcp(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final response = await _rpc({
          'jsonrpc': '2.0',
          'id': 0,
          'method': 'initialize',
          'params': <String, dynamic>{},
        });
        if (response['result'] != null) return true;
      } on Object {
        // Not listening yet.
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return false;
  }

  /// Kills the process and removes its throwaway home.
  Future<void> dispose() async {
    _http.close(force: true);
    _process.kill(ProcessSignal.sigterm);
    await _process.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    if (_home.existsSync()) _home.deleteSync(recursive: true);
  }
}

/// A set of app instances sharing one server, torn down together.
class AppFleet {
  AppFleet._(this.harness, this.skipReason);

  final IntegrationHarness harness;

  /// Non-null when the fleet can't run — pass as a group's `skip:`.
  final String? skipReason;

  final List<AppInstance> _instances = [];
  int _nextPort = 39150;

  /// Resolves a server and an app bundle, or explains why it can't.
  static Future<AppFleet> resolve() async {
    final harness = await IntegrationHarness.resolve();
    if (harness.skipReason != null) {
      return AppFleet._(harness, harness.skipReason);
    }
    try {
      AppInstance.resolveBinary();
    } on AppUnavailable catch (e) {
      return AppFleet._(harness, e.message);
    }
    if (Platform.environment['DISPLAY'] == null &&
        Platform.environment['WAYLAND_DISPLAY'] == null) {
      return AppFleet._(
        harness,
        'No DISPLAY. These launch real app windows — run under xvfb '
        '(`xvfb-run -a flutter test multi_instance/`) or on a desktop session.',
      );
    }
    return AppFleet._(harness, null);
  }

  /// Registers an account and launches an app signed in as it.
  Future<AppInstance> spawn(String label, {TestAccount? account}) async {
    final resolved = account ?? await harness.newAccount(label);
    final instance = await AppInstance.launch(
      account: resolved,
      label: label,
      port: _nextPort++,
    );
    _instances.add(instance);
    return instance;
  }

  Future<void> dispose() async {
    for (final instance in _instances) {
      await instance.dispose();
    }
    _instances.clear();
    await harness.dispose();
  }
}
