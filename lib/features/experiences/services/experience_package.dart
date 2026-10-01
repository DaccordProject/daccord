import 'dart:convert';
import 'package:accordkit/accordkit.dart';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:experience_runtime/experience_runtime.dart';

/// Validate an authenticated community-server release against the pinned session
/// identity and its operator-provisioned publication key before guest execution.
Future<ExperienceModule> validateExperiencePackage(
  Map release, {
  required String digest,
  required String gameId,
  required String version,
  required String platform,
}) async {
  if (release['status'] != 'approved' ||
      release['digest'] != digest ||
      (release['payload'] as String).length > 200000) {
    throw const FormatException('Release no longer approved');
  }
  final payload = base64Decode(release['payload'] as String);
  if (payload.length > 100000 || sha256.convert(payload).toString() != digest) {
    throw const FormatException('Package integrity check failed');
  }
  List<int> hex(String value, int expectedLength) {
    if (value.length != expectedLength * 2 ||
        !RegExp(r'^[0-9a-f]+$').hasMatch(value)) {
      throw const FormatException('Invalid signature encoding');
    }
    return [
      for (var i = 0; i < value.length; i += 2)
        int.parse(value.substring(i, i + 2), radix: 16),
    ];
  }

  final verified = await Ed25519().verify(
    payload,
    signature: Signature(
      hex(release['signature'] as String, 64),
      publicKey: SimplePublicKey(
        hex(release['verification_key'] as String, 32),
        type: KeyPairType.ed25519,
      ),
    ),
  );
  if (!verified) {
    throw const FormatException('Package signature verification failed');
  }
  final package = jsonDecode(utf8.decode(payload)) as Map;
  final manifest = AccordExperienceManifest.fromJson(
    Map<String, dynamic>.from(package['manifest'] as Map),
  );
  if (manifest.id != gameId ||
      manifest.version != version ||
      manifest.hostApi != 1 ||
      manifest.runtime != 'wasm-bounded-v1' ||
      manifest.capabilities.join(',') != 'session.read,session.action,draw') {
    throw const FormatException('Incompatible experience');
  }
  if (!manifest.platforms.contains(platform)) {
    throw StateError('This experience is unavailable on $platform.');
  }
  if ((package['module'] as String).length > 90000) {
    throw const FormatException('Module too large');
  }
  final bytes = base64Decode(package['module'] as String);
  if (sha256.convert(bytes).toString() != manifest.moduleSha256) {
    throw const FormatException('Module integrity check failed');
  }
  return ExperienceModule.decode(bytes);
}
