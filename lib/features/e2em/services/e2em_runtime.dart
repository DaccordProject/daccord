import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bonfire/features/e2em/services/e2em_runtime_stub.dart'
    if (dart.library.io) 'package:bonfire/features/e2em/services/e2em_runtime_desktop.dart'
    as platform;

class E2emUnavailable implements Exception {
  const E2emUnavailable(this.code);
  final String code;
}

class E2emRuntimeStatus {
  const E2emRuntimeStatus(this.ready, this.message);
  final bool ready;
  final String message;
}

/// The SDK verifies the wire report; the app retains its exact request binding.
class E2emReport {
  E2emReport({
    required this.status,
    required this.action,
    required this.complete,
    required Map<String, dynamic> request,
    this.categories = const [],
  }) : _snapshot = jsonEncode(request);

  final String status;
  final String action;
  final bool complete;
  final List<String> categories;
  final String _snapshot;

  bool appliesTo(Map<String, dynamic> request) =>
      jsonEncode(request) == _snapshot;
}

abstract class E2emRuntime {
  bool get supported;
  Future<E2emRuntimeStatus> check(Map<String, dynamic> policy);
  Future<E2emReport> assess(Map<String, dynamic> request);
  Future<void> connectApp();
  void close();
}

final e2emRuntimeProvider = Provider<E2emRuntime>((ref) {
  final runtime = platform.createRuntime();
  ref.onDispose(runtime.close);
  return runtime;
});
