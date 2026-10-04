import 'dart:async';

import 'package:bonfire/features/e2em/models/e2em_preferences.dart';
import 'package:bonfire/features/e2em/services/e2em_runtime.dart';
import 'package:bonfire/features/e2em/services/e2em_send_guard.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeRuntime implements E2emRuntime {
  @override
  bool supported = true;
  int calls = 0;
  String action = 'allow';
  String status = 'assessed';
  bool complete = true;
  bool stale = false;
  bool fail = false;
  Completer<void>? pending;
  Map<String, dynamic>? request;

  @override
  Future<E2emReport> assess(Map<String, dynamic> request) async {
    calls++;
    this.request = request;
    if (pending != null) await pending!.future;
    if (fail) throw const E2emUnavailable('DEADLINE_EXCEEDED');
    return E2emReport(
      status: status,
      action: action,
      complete: complete,
      categories: ['pii.email'],
      request: stale ? {...request, 'direction': 'incoming'} : request,
    );
  }

  @override
  Future<E2emRuntimeStatus> check(Map<String, dynamic> policy) async =>
      const E2emRuntimeStatus(true, 'Ready');
  @override
  Future<void> connectApp() async {}
  @override
  void close() {}
}

void main() {
  late FakeRuntime runtime;
  late E2emPreferences selected;
  late E2emSendGuard guard;
  late bool sessionCurrent;
  late bool confirmed;
  late int confirmations;
  Future<bool> Function()? confirmation;

  setUp(() {
    runtime = FakeRuntime();
    selected = const E2emPreferences(enabled: true, categories: ['pii.email']);
    sessionCurrent = true;
    confirmed = false;
    confirmations = 0;
    confirmation = null;
    guard = E2emSendGuard(
      runtime: runtime,
      preferences: () => selected,
      isSessionCurrent: () => sessionCurrent,
      confirmWarning: (text, categories) async {
        expect(text, 'Contact test@example.com');
        confirmations++;
        return confirmation == null ? confirmed : await confirmation!();
      },
    );
  });

  test(
    'assessed allow grants only the checked settings/session snapshot',
    () async {
      final result = await guard.call('channel', {'content': 'Hello'});
      expect(result.failure, isNull);
      expect(runtime.request!['message']['text'], 'Hello');
      selected = selected.copyWith(response: E2emResponse.review);
      expect(result.failure?.code, 'message_check_stale');
    },
  );

  test(
    'disabled personal checks do not connect but are invalidated if enabled in flight',
    () async {
      selected = selected.copyWith(enabled: false);
      final result = await guard.call('channel', {'content': 'Hello'});
      expect(result.failure, isNull);
      expect(runtime.calls, 0);
      selected = selected.copyWith(enabled: true);
      expect(result.failure, isNotNull);
    },
  );

  test(
    'warn needs explicit confirmation specific to the outgoing text',
    () async {
      runtime.action = 'warn';
      expect(
        (await guard.call('channel', {
          'content': 'Contact test@example.com',
        })).failure,
        isNotNull,
      );
      confirmed = true;
      expect(
        (await guard.call('channel', {
          'content': 'Contact test@example.com',
        })).failure,
        isNull,
      );
      expect(confirmations, 2);
      expect(runtime.calls, 2);
    },
  );

  test(
    'review, block, errors, incomplete coverage, and stale reports hold without confirmation',
    () async {
      for (final action in ['review', 'block', 'unknown']) {
        runtime.action = action;
        expect(
          (await guard.call('c', {'content': 'Hello'})).failure,
          isNotNull,
        );
      }
      runtime.action = 'allow';
      runtime.status = 'indeterminate';
      expect((await guard.call('c', {'content': 'Hello'})).failure, isNotNull);
      runtime.status = 'assessed';
      runtime.complete = false;
      expect((await guard.call('c', {'content': 'Hello'})).failure, isNotNull);
      runtime.complete = true;
      runtime.stale = true;
      expect((await guard.call('c', {'content': 'Hello'})).failure, isNotNull);
      runtime.stale = false;
      runtime.fail = true;
      expect((await guard.call('c', {'content': 'Hello'})).failure, isNotNull);
      expect(confirmations, 0);
    },
  );

  test(
    'hold-for-editing forbids overriding even an unexpected warn result',
    () async {
      selected = selected.copyWith(response: E2emResponse.review);
      runtime.action = 'warn';
      confirmed = true;
      expect((await guard.call('c', {'content': 'Hello'})).failure, isNotNull);
      expect(confirmations, 0);
    },
  );

  test('changing settings during inference discards the result', () async {
    runtime.pending = Completer<void>();
    final result = guard.call('c', {'content': 'Hello'});
    selected = selected.copyWith(threshold: 0.5);
    runtime.pending!.complete();
    expect((await result).failure, isNotNull);
  });

  test(
    'changing account during confirmation invalidates approval at the final boundary',
    () async {
      runtime.action = 'warn';
      confirmation = () async {
        sessionCurrent = false;
        return true;
      };
      expect(
        (await guard.call('c', {
          'content': 'Contact test@example.com',
        })).failure,
        isNotNull,
      );
    },
  );

  test(
    'unsupported devices and outgoing embeds hold text when checks are enabled',
    () async {
      runtime.supported = false;
      expect((await guard.call('c', {'content': 'Hello'})).failure, isNotNull);
      runtime.supported = true;
      expect(
        (await guard.call('c', {
          'content': 'Hello',
          'embeds': [
            {'description': 'Secret'},
          ],
        })).failure,
        isNotNull,
      );
      expect(runtime.calls, 0);
    },
  );
}
