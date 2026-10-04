import 'dart:io';

import 'package:e2em_local/e2em.dart' as sdk;

import 'package:bonfire/features/e2em/services/e2em_runtime.dart';
import 'package:bonfire/features/e2em/services/e2em_runtime_stub.dart';

E2emRuntime createRuntime() =>
    Platform.isLinux || Platform.isMacOS || Platform.isWindows
    ? DesktopE2emRuntime()
    : UnsupportedE2emRuntime();

class DesktopE2emRuntime implements E2emRuntime {
  DesktopE2emRuntime({this.app = 'daccord'});
  final String app;
  Future<sdk.Client>? _pending;
  sdk.Client? _client;
  bool _disposed = false;

  @override
  bool get supported => true;

  Future<sdk.Client> _connect() async {
    if (_disposed) throw const E2emUnavailable('CANCELLED');
    if (_client != null) return _client!;
    try {
      final client = await (_pending ??= sdk.Client.connect(app: app));
      if (_disposed) {
        client.close();
        throw const E2emUnavailable('CANCELLED');
      }
      _client = client;
      return client;
    } on sdk.E2EMError catch (error) {
      throw E2emUnavailable(error.code);
    } finally {
      _pending = null;
    }
  }

  void _disconnect() {
    _client?.close();
    _client = null;
  }

  @override
  Future<E2emRuntimeStatus> check(Map<String, dynamic> policy) async {
    try {
      final client = await _connect();
      final capabilities = await client.capabilities();
      if (capabilities['backend_ready'] != true) {
        return const E2emRuntimeStatus(
          false,
          'E2EM’s local model is unavailable.',
        );
      }
      await client.validatePolicy(policy);
      return const E2emRuntimeStatus(
        true,
        'Connected. Your rule configuration is valid. Coverage is checked for each message.',
      );
    } on sdk.E2EMError catch (error) {
      _disconnect();
      return E2emRuntimeStatus(false, _explanation(error.code));
    } on E2emUnavailable catch (error) {
      return E2emRuntimeStatus(false, _explanation(error.code));
    }
  }

  @override
  Future<E2emReport> assess(Map<String, dynamic> request) async {
    try {
      final client = await _connect();
      final report = await client.assess(request);
      if (!report.appliesTo(request)) {
        throw const E2emUnavailable('STALE_RESULT');
      }
      final rules = {
        for (final rule in request['policy']['rules'] as List)
          rule['id']: rule as Map<String, dynamic>,
      };
      return E2emReport(
        status: report.status,
        action: report.action,
        complete:
            report.coverage['target_complete'] == true &&
            report.coverage['context_complete'] == true &&
            report.unevaluated.isEmpty,
        request: request,
        categories: List.unmodifiable(
          report.findings
              .where((finding) {
                final rule = rules[finding['rule_id']];
                if (rule == null) return false;
                if (rule['match'] == 'detected') return true;
                final score = finding['score'] as num?;
                final threshold = rule['action_threshold'] as num?;
                // Custom rules use provider-owned thresholds; do not invent a
                // category-specific cause when that threshold is unavailable.
                return score != null && threshold != null && score >= threshold;
              })
              .map((finding) => finding['category'] as String? ?? 'Custom rule')
              .toSet(),
        ),
      );
    } on sdk.E2EMError catch (error) {
      _disconnect();
      throw E2emUnavailable(error.code);
    }
  }

  @override
  Future<void> connectApp() async {
    _disconnect();
    try {
      await Process.start(
        Platform.isWindows ? 'e2em-setup.exe' : 'e2emd',
        ['--setup', '--setup-app', app],
        mode: ProcessStartMode.detached,
      );
    } on ProcessException {
      throw const E2emUnavailable('SETUP_UNAVAILABLE');
    }
  }

  @override
  void close() {
    _disposed = true;
    _disconnect();
  }
}

String _explanation(String code) => switch (code) {
  'UNSUPPORTED_POLICY' || 'INVALID_POLICY' =>
    'The installed runtime cannot honour these rules. Update E2EM or revise your settings.',
  'DEADLINE_EXCEEDED' => 'E2EM timed out. Check the runtime and try again.',
  _ =>
    'Unable to connect. Install E2EM, connect Daccord in setup, then check again.',
};
