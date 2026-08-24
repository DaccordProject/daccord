import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Minimal credential-vault boundary used by session persistence.
abstract interface class SessionCredentialVault {
  Future<void> write(String reference, String token);
  Future<String?> read(String reference);
  Future<void> delete(String reference);
}

/// Platform credential storage: Keychain, Android Keystore, Windows credential
/// protection, Linux Secret Service, or the package's WebCrypto backend.
class PlatformSessionCredentialVault implements SessionCredentialVault {
  PlatformSessionCredentialVault({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _keyPrefix = 'daccord.session.v1.';
  final FlutterSecureStorage _storage;

  String _key(String reference) => '$_keyPrefix$reference';

  @override
  Future<void> write(String reference, String token) =>
      _storage.write(key: _key(reference), value: token);

  @override
  Future<String?> read(String reference) => _storage.read(key: _key(reference));

  @override
  Future<void> delete(String reference) =>
      _storage.delete(key: _key(reference));
}
