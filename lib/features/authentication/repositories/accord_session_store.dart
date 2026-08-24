import 'dart:convert';
import 'dart:math';

import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/session_credential_vault.dart';
import 'package:bonfire/features/profiles/services/profile_store.dart';
import 'package:hive_ce/hive.dart';

/// Persists session metadata in Hive and bearer tokens in the platform vault.
///
/// Hive contains only random opaque `credentialRef` values. Records written by
/// older releases are migrated by writing their token to the vault first and
/// scrubbing plaintext from Hive only after that succeeds. A vault failure
/// therefore fails closed without destroying the only usable credential.
class AccordSessionStore {
  AccordSessionStore({
    SessionCredentialVault? credentialVault,
    String Function()? createReference,
  }) : _credentials = credentialVault ?? PlatformSessionCredentialVault(),
       _createReference = createReference ?? _randomReference;

  static const _sessionKey = 'session';
  static const _accountsKey = 'accounts';
  static const _credentialRefKey = 'credentialRef';
  static final _validReference = RegExp(r'^[A-Za-z0-9_-]{32,}$');

  final SessionCredentialVault _credentials;
  final String Function() _createReference;

  Future<Box> _box() => Hive.openBox(ProfileStore.activeSessionBoxName);

  /// Persists [session] as active and upserts it into the saved-account list.
  /// One account per server is retained, matching the live connection model.
  Future<void> persist(AccordSession session) async {
    if (session.isGuest || session.isExpired) return;
    final box = await _box();
    final accounts = _accountsFrom(box);
    final reference = _referenceFor(session, box, accounts);

    // Vault first, Hive second: never replace the only plaintext copy with a
    // reference that cannot yet be resolved.
    await _credentials.write(reference, session.token);
    final metadata = _metadata(session, reference);
    final removedReferences = <String>{};
    accounts.removeWhere((key, raw) {
      if (key == session.key ||
          _rawServerBaseUrl(raw) != session.server.baseUrl) {
        return false;
      }
      final oldReference = _referenceFrom(raw);
      if (oldReference != null) removedReferences.add(oldReference);
      return true;
    });
    accounts[session.key] = metadata;
    await box.put(_sessionKey, metadata);
    await box.put(_accountsKey, accounts);

    for (final oldReference in removedReferences) {
      if (oldReference != reference) await _credentials.delete(oldReference);
    }
  }

  /// Changes the active pointer without rewriting the saved-account list.
  Future<void> persistActive(AccordSession session) async {
    if (session.isGuest || session.isExpired) return;
    final box = await _box();
    final accounts = _accountsFrom(box);
    final reference = _referenceFor(session, box, accounts);
    await _credentials.write(reference, session.token);
    await box.put(_sessionKey, _metadata(session, reference));
  }

  /// Active session eligible for restart. Legacy plaintext is migrated before
  /// the hydrated in-memory session is returned.
  Future<AccordSession?> readRestorableActive() async {
    final box = await _box();
    final hydrated = await _hydrate(box.get(_sessionKey));
    if (hydrated == null) return null;
    final session = hydrated.session;
    if (session.isGuest || session.isExpired) {
      await deleteActive();
      return null;
    }
    if (hydrated.needsScrub) {
      await box.put(_sessionKey, _metadata(session, hydrated.reference));
    }
    return session;
  }

  /// Returns hydrated JSON for legacy auth code that owns its own parsing. The
  /// value exists only in memory; the Hive record remains token-free.
  Future<Object?> readActiveRaw() async {
    final session = await readRestorableActive();
    return session?.toJson();
  }

  /// Deletes the active pointer. Its vault item is deleted only when no saved
  /// account still references it.
  Future<void> deleteActive() async {
    final box = await _box();
    final reference = _referenceFrom(box.get(_sessionKey));
    await box.delete(_sessionKey);
    if (reference != null &&
        !_accountsReference(_accountsFrom(box), reference)) {
      await _credentials.delete(reference);
    }
  }

  /// Removes a saved account and deletes its vault item once no active pointer
  /// still needs it.
  Future<void> removeAccount(String key) async {
    final box = await _box();
    final accounts = _accountsFrom(box);
    final reference = _referenceFrom(accounts.remove(key));
    await box.put(_accountsKey, accounts);
    if (reference != null &&
        _referenceFrom(box.get(_sessionKey)) != reference) {
      await _credentials.delete(reference);
    }
  }

  /// All saved accounts, with malformed or unavailable vault entries skipped.
  /// Legacy plaintext entries are migrated and scrubbed in one Hive rewrite.
  Future<List<AccordSession>> listAccounts() async {
    final box = await _box();
    final accounts = _accountsFrom(box);
    final migrated = <String, dynamic>{};
    final result = <AccordSession>[];
    var changed = false;

    for (final entry in accounts.entries) {
      try {
        final hydrated = await _hydrate(entry.value);
        if (hydrated == null) {
          migrated[entry.key] = entry.value;
          continue;
        }
        final session = hydrated.session;
        if (session.isGuest || session.isExpired) {
          changed = true;
          if (_referenceFrom(entry.value) != null) {
            await _credentials.delete(hydrated.reference);
          }
          continue;
        }
        migrated[session.key] = _metadata(session, hydrated.reference);
        result.add(session);
        changed = changed || hydrated.needsScrub || entry.key != session.key;
      } catch (_) {
        // A malformed entry or temporarily unavailable credential vault must
        // not crash the switcher. Keep it for a later recovery attempt.
        migrated[entry.key] = entry.value;
      }
    }
    if (changed) await box.put(_accountsKey, migrated);
    return result;
  }

  Future<({AccordSession session, String reference, bool needsScrub})?>
  _hydrate(Object? raw) async {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final plaintext = json['token'] as String?;
    var reference = _referenceFrom(json);
    if (reference == null) {
      if (plaintext == null || plaintext.isEmpty) return null;
      reference = _newReference();
    }
    final token = plaintext?.isNotEmpty == true
        ? plaintext!
        : await _credentials.read(reference);
    if (token == null || token.isEmpty) return null;
    json['token'] = token;
    final session = AccordSession.fromJson(json);
    // Guest and expired records are purged, never promoted into the vault.
    if (plaintext?.isNotEmpty == true &&
        !session.isGuest &&
        !session.isExpired) {
      await _credentials.write(reference, token);
    }
    return (
      session: session,
      reference: reference,
      needsScrub: raw.containsKey('token'),
    );
  }

  Map<String, dynamic> _metadata(AccordSession session, String reference) {
    final json = session.toJson()..remove('token');
    json[_credentialRefKey] = reference;
    return json;
  }

  String _referenceFor(
    AccordSession session,
    Box box,
    Map<String, dynamic> accounts,
  ) {
    final accountReference = _referenceFrom(accounts[session.key]);
    if (accountReference != null) return accountReference;
    final active = box.get(_sessionKey);
    if (_rawSessionKey(active) == session.key) {
      final activeReference = _referenceFrom(active);
      if (activeReference != null) return activeReference;
    }
    return _newReference();
  }

  String _newReference() {
    final reference = _createReference();
    if (!_validReference.hasMatch(reference)) {
      throw StateError(
        'Credential reference generator returned an unsafe value',
      );
    }
    return reference;
  }

  String? _referenceFrom(Object? raw) {
    if (raw is! Map) return null;
    final value = raw[_credentialRefKey];
    if (value is! String || !_validReference.hasMatch(value)) return null;
    return value;
  }

  String? _rawSessionKey(Object? raw) {
    if (raw is! Map) return null;
    final userId = raw['userId'];
    final server = raw['server'];
    if (userId is! String || server is! Map) return null;
    final baseUrl = server['baseUrl'];
    return baseUrl is String ? '$userId@$baseUrl' : null;
  }

  String? _rawServerBaseUrl(Object? raw) {
    if (raw is! Map || raw['server'] is! Map) return null;
    final value = (raw['server'] as Map)['baseUrl'];
    return value is String ? value : null;
  }

  bool _accountsReference(Map<String, dynamic> accounts, String reference) =>
      accounts.values.any((raw) => _referenceFrom(raw) == reference);

  Map<String, dynamic> _accountsFrom(Box box) {
    final raw = box.get(_accountsKey);
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  static String _randomReference() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
