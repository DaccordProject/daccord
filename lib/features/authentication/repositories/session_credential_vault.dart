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

  /// Serializes vault operations across all instances in this isolate.
  ///
  /// The Linux backend keeps the *whole* vault in a single Secret Service item
  /// and rewrites it wholesale on each call (read the JSON blob → patch one key
  /// → store the blob back). Two overlapping operations therefore race on that
  /// blob and the loser's key is silently dropped — stranding a `credentialRef`
  /// that Hive still points at, which [AccordSessionStore] can only read as "no
  /// session", i.e. a surprise logout. Restoring a session does exactly this:
  /// `_makeActive` fires an un-awaited `persistActive` write that overlaps the
  /// `listAccounts` migration pass. Chaining keeps the read-modify-write cycles
  /// from interleaving; on the per-key backends it is simply a no-op cost.
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
