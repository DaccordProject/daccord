import 'dart:convert';
import 'dart:io';
import 'package:bonfire/features/experiences/services/experience_package.dart';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'execution requires an exact signed payload, pinned scope and supported platform',
    () async {
      final payload = await File(
        'tools/experiences/packages/chess.json',
      ).readAsBytes();
      final algorithm = Ed25519();
      final key = await algorithm.newKeyPairFromSeed(List.filled(32, 1));
      final public = await key.extractPublicKey();
      final signature = await algorithm.sign(payload, keyPair: key);
      String hex(List<int> bytes) =>
          bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final digest = sha256.convert(payload).toString();
      final release = {
        'status': 'approved',
        'digest': digest,
        'payload': base64Encode(payload),
        'signature': hex(signature.bytes),
        'verification_key': hex(public.bytes),
      };
      Future<void> validate(
        Map value, {
        String game = 'chess',
        String platform = 'linux',
      }) async {
        final module = await validateExperiencePackage(
          value,
          digest: digest,
          gameId: game,
          version: '1.0.0',
          platform: platform,
        );
        expect(
          module
              .invoke(
                'render',
                [],
                readState: (k, i) => 0,
                grantValid: () => true,
              )
              .drawings
              .length,
          64,
        );
      }

      await validate(release);
      await expectLater(
        validate({...release, 'status': 'revoked'}),
        throwsFormatException,
      );
      await expectLater(
        validate({...release, 'signature': '00' * 64}),
        throwsFormatException,
      );
      await expectLater(
        validate({...release, 'verification_key': '00' * 32}),
        throwsFormatException,
      );
      await expectLater(
        validate({
          ...release,
          'payload': base64Encode([...payload, 0]),
        }),
        throwsFormatException,
      );
      await expectLater(
        validate(release, game: 'other-space-game'),
        throwsFormatException,
      );
      await expectLater(
        validate(release, platform: 'unsupported'),
        throwsStateError,
      );
    },
  );
}
