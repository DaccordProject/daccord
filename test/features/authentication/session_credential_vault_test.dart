import 'dart:async';

import 'package:bonfire/features/authentication/repositories/session_credential_vault.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('different vault instances serialize shared-store writes', () async {
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    var values = <String, String>{};
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      // Model the Linux backend's read-modify-write of the entire vault.
      final snapshot = Map<String, String>.of(values);
      calls++;
      if (calls == 1) {
        firstStarted.complete();
        await releaseFirst.future;
      }
      final args = call.arguments as Map;
      snapshot[args['key'] as String] = args['value'] as String;
      values = snapshot;
      return null;
    });
    final first = PlatformSessionCredentialVault().write('first', 'token-a');
    await firstStarted.future;
    final second = PlatformSessionCredentialVault().write('second', 'token-b');
    await Future<void>.delayed(Duration.zero);
    final callsWhileBlocked = calls;
    releaseFirst.complete();
    await Future.wait([first, second]);
    expect(callsWhileBlocked, 1);
    expect(values.values, unorderedEquals(['token-a', 'token-b']));
  });

  test('a failed operation does not block later writes or reads', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (++calls == 1) throw PlatformException(code: 'locked');
      return call.method == 'read' ? 'recovered-token' : null;
    });
    final vault = PlatformSessionCredentialVault();
    await expectLater(
      vault.write('account', 'old-token'),
      throwsA(isA<PlatformException>()),
    );
    await vault.write('account', 'recovered-token');
    expect(await vault.read('account'), 'recovered-token');
    await vault.delete('account');
    expect(calls, 4);
  });
}
