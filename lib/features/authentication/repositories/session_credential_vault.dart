import 'package:flutter/foundation.dart';
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
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // Ad hoc Debug/Profile builds have no provisioned application ID.
            // Use the encrypted login Keychain there; provisioned production
            // builds retain the existing data-protection Keychain namespace.
            mOptions: MacOsOptions(usesDataProtectionKeychain: kReleaseMode),
          );

  static const _keyPrefix = 'daccord.session.v1.';
  final FlutterSecureStorage _storage;

  /// Serializes vault operations across all instances in this isolate. The
  /// Linux backend rewrites the whole vault (one Secret Service item) on every
  /// call, so overlapping operations — e.g. session restore's un-awaited
  /// `persistActive` racing the `listAccounts` migration — silently drop a key
  /// and strand a `credentialRef` Hive still points at: a surprise logout.
  /// On per-key backends the chaining is just a no-op cost.
  static Future<void> _queue = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = _queue.then((_) => operation());
    // The chain only orders work, so a failed operation must not poison it —
    // the error still surfaces to the caller through [result].
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  String _key(String reference) => '$_keyPrefix$reference';

  @override
  Future<void> write(String reference, String token) =>
      _serialized(() => _storage.write(key: _key(reference), value: token));

  @override
  Future<String?> read(String reference) =>
      _serialized(() => _storage.read(key: _key(reference)));

  @override
  Future<void> delete(String reference) =>
      _serialized(() => _storage.delete(key: _key(reference)));
}
