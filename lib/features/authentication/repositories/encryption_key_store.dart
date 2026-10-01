import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/repositories/session_credential_vault.dart';

/// Shares serialization with session vault writes on Linux Secret Service.
class PlatformEncryptionKeyStore implements EncryptionKeyStore {
  final SessionCredentialVault _vault = PlatformSessionCredentialVault();
  @override
  Future<String?> read(String key) => _vault.read(key);
  @override
  Future<void> write(String key, String value) => _vault.write(key, value);
}
