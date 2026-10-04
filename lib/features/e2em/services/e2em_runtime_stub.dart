import 'package:bonfire/features/e2em/services/e2em_runtime.dart';

E2emRuntime createRuntime() => UnsupportedE2emRuntime();

class UnsupportedE2emRuntime implements E2emRuntime {
  @override
  bool get supported => false;
  @override
  Future<E2emRuntimeStatus> check(Map<String, dynamic> policy) async =>
      const E2emRuntimeStatus(false, 'E2EM currently supports desktop only.');
  @override
  Future<E2emReport> assess(Map<String, dynamic> request) async =>
      throw const E2emUnavailable('UNSUPPORTED_PLATFORM');
  @override
  Future<void> connectApp() async =>
      throw const E2emUnavailable('UNSUPPORTED_PLATFORM');
  @override
  void close() {}
}
