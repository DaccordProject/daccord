import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import '../models/attachment.dart';
import '../utils/cdn.dart';
import '../models/message.dart';
import '../rest/accord_rest.dart';
import '../rest/rest_result.dart';
import 'encryption_device.dart';

/// Implement with a credential vault, never an unencrypted preferences store.
abstract interface class EncryptionKeyStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class EncryptionException implements Exception {
  final String message;
  const EncryptionException(this.message);
  @override
  String toString() => message;
}

/// The server refuses this device's registration outright (device-key
/// mismatch, device limit, …). Kept until [PrivateChatEncryption.importBackup]
/// or the next app start: retrying cannot succeed and spent a request per
/// history page or preview, exhausting the per-user rate limit.
class _RegistrationRefused extends EncryptionException {
  const _RegistrationRefused(super.message);
}

/// One account key version from the private keyring.
class _Account {
  final int version;
  final SimpleKeyPair exchange;
  final SimpleKeyPair signing;
  final String exchangeKey;
  final String signingKey;
  final String exchangePrivate;
  final String signingPrivate;
  const _Account(this.version, this.exchange, this.signing, this.exchangeKey,
      this.signingKey, this.exchangePrivate, this.signingPrivate);
  Map<String, dynamic> get secret => {
        'version': version,
        'exchange_private': exchangePrivate,
        'signing_private': signingPrivate,
      };
  Map<String, dynamic> get public => {
        'version': version,
        'exchange_key': exchangeKey,
        'signing_key': signingKey,
      };
  bool sameAs(_Account other) =>
      version == other.version &&
      exchangePrivate == other.exchangePrivate &&
      signingPrivate == other.signingPrivate;
}

/// This device's own key (never leaves the device).
class _Device {
  final String id;
  final SimpleKeyPair exchange;
  final SimpleKeyPair signing;
  final String exchangeKey;
  final String signingKey;
  final String exchangePrivate;
  final String signingPrivate;
  const _Device(this.id, this.exchange, this.signing, this.exchangeKey,
      this.signingKey, this.exchangePrivate, this.signingPrivate);
}

typedef _Compared = ({
  String exchangeKey,
  String signingKey,
  String accountKey
});

/// Private chat encryption.
///
/// v2 (`daccord-e2ee:2:`): an account keyring (version 1 is the v1 identity)
/// certifies per-device keys; messages are signed by the sending device and
/// the content key is wrapped for every participant's current account key and
/// each of their active devices. New devices are approved from an existing one
/// by comparing a link code on both devices; removing devices rotates the
/// account key. v1 (`daccord-e2ee:1:`) history stays readable. No server
/// secret, shared group key, plaintext fallback, or forward-secrecy claim.
class PrivateChatEncryption {
  static const prefixV1 = 'daccord-e2ee:1:';
  static const prefixV2 = 'daccord-e2ee:2:';

  /// Prefix of the messages this client sends.
  static const prefix = prefixV2;
  static const pendingMessage =
      "This device isn't approved for encrypted chats yet.";
  static const blockedMessage =
      "Your encryption keys don't match the server. Sending and decryption are blocked.";

  final AccordRest rest;
  final EncryptionKeyStore store;
  final String userId;

  /// User-visible label registered for this device (1–64 characters).
  final String deviceName;

  static final X25519 _exchange = X25519();
  static final Ed25519 _signing = Ed25519();
  static final AesGcm _cipher = AesGcm.with256bits();
  static final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final RegExp _deviceIdPattern = RegExp(r'^[A-Za-z0-9_-]{22}$');

  List<_Account> _keyring = [];

  /// The keyring was accepted by the server as this account's (registration,
  /// confirmed approval, backup or rotation). A migrated v1 identity the
  /// server never accepted is not, and may be replaced by an approval.
  bool _confirmed = false;
  _Device? _device;
  String? _userContext;

  /// Current account signing key the displayed link code was computed from;
  /// fixed when this device first registers pending.
  String? _linkAccountKey;

  /// An approval package's keyring awaiting [confirmApproval].
  List<_Account>? _staged;

  /// Never accept an own account below this version (no rollback).
  int _floorVersion = 0;

  /// Own devices this one has seen removed; they never count as active again.
  final Map<String, Map<String, dynamic>> _floorRevoked = {};
  PrivateChatSetup _setup = PrivateChatSetup.unknown;
  Future<void>? _initializing;
  final Map<String, Map<String, dynamic>> _trusted = {};
  final Map<String, String> _channels = {};
  final Map<String, String> _selves = {};
  final Map<String, String> _cdns = {};
  final Map<String, Map<String, String>> _aliases = {};
  final Map<String, _Compared> _compared = {};
  final _setupChanges = StreamController<PrivateChatSetup>.broadcast();
  final _devicePending = StreamController<EncryptionDevice>.broadcast();
  final _devicesUpdate = StreamController<void>.broadcast();
  static final Map<String, Future<void>> _storageQueues = {};
  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = (_storageQueues[_scope] ?? Future<void>.value())
        .then((_) => operation());
    _storageQueues[_scope] = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  PrivateChatEncryption(this.rest, this.store, this.userId,
      {String deviceName = 'Daccord'})
      : deviceName = _cleanName(deviceName);

  static String _cleanName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Daccord';
    return String.fromCharCodes(trimmed.runes.take(64));
  }

  String get _scope => base64Url.encode(utf8.encode('${rest.baseUrl}|$userId'));
  bool knowsPrivateChat(String channelId) => _channels.containsKey(channelId);
  String get _identityKey => 'e2ee.v1.$_scope.identity';
  String get _trustKey => 'e2ee.v1.$_scope.trust';
  String get _keyringKey => 'e2ee.v2.$_scope.keyring';
  String get _deviceKey => 'e2ee.v2.$_scope.device';
  String get _rotationKey => 'e2ee.v2.$_scope.rotation';
  String get _approvalKey => 'e2ee.v2.$_scope.approval';
  String get _floorKey => 'e2ee.v2.$_scope.floor';
  String get _context => _userContext ?? userId;

  /// Whether this device can read and send private chats.
  PrivateChatSetup get setup => _setup;

  /// Emits whenever [setup] changes. Also re-emits [PrivateChatSetup.pending]
  /// whenever this device's link code changed (re-read [linkCode] then).
  Stream<PrivateChatSetup> get setupChanges => _setupChanges.stream;

  /// Another device of this account asks for approval
  /// (`encryption.device_pending`).
  Stream<EncryptionDevice> get onDevicePending => _devicePending.stream;

  /// The account's device list changed (`encryption.devices_update`).
  Stream<void> get onDevicesUpdate => _devicesUpdate.stream;

  void _setSetup(PrivateChatSetup value, {bool force = false}) {
    if (_setup == value && !force) return;
    _setup = value;
    if (!_setupChanges.isClosed) _setupChanges.add(value);
  }

  void _block() => _setSetup(PrivateChatSetup.blocked);

  /// Routes gateway `encryption.*` events; [AccordClient] calls this.
  void handleGatewayEvent(String type, Map<String, dynamic> data) {
    switch (type) {
      case 'encryption.device_pending':
        try {
          final device =
              EncryptionDevice.fromJson(data, currentDeviceId: _device?.id);
          if (!device.current && !_devicePending.isClosed) {
            _devicePending.add(device);
          }
        } catch (_) {}
      case 'encryption.devices_update':
        if (!_devicesUpdate.isClosed) _devicesUpdate.add(null);
        unawaited(checkApproval().then((_) {}, onError: (Object _) {}));
    }
  }

  Future<void> dispose() async {
    await _setupChanges.close();
    await _devicePending.close();
    await _devicesUpdate.close();
  }

  // ── Startup ───────────────────────────────────────────────────────────────

  /// Loads the keyring and device key and registers this device. Completes
  /// normally in every [setup] state (pending, approved and blocked too). A
  /// transient failure is retried by the next caller.
  Future<void> initialize() => _initializing ??= _serialized(() async {
        await _loadLocal();
        await _register();
      }).catchError((Object e) {
        if (e is! _RegistrationRefused) _initializing = null;
        throw e;
      });

  Future<void> _loadLocal() async {
    var ring = await store.read(_keyringKey);
    if (ring == null || ring.isEmpty) {
      // The v1 identity becomes account version 1; the v1 entry is kept. It
      // is confirmed once the server shows it as the account's key.
      final v1 = await store.read(_identityKey);
      if (v1 != null && v1.isNotEmpty) {
        final secret = jsonDecode(v1) as Map;
        ring = jsonEncode({
          'accounts': [
            {
              'version': 1,
              'exchange_private': secret['exchange_private'],
              'signing_private': secret['signing_private'],
            }
          ],
          'confirmed': false,
        });
        await _parseKeyring(ring);
        await store.write(_keyringKey, ring);
      }
    }
    if (ring == null || ring.isEmpty) {
      _keyring = [];
      _confirmed = false;
    } else {
      _keyring = await _parseKeyring(ring);
      _confirmed = (jsonDecode(ring) as Map)['confirmed'] != false;
    }
    final device = await store.read(_deviceKey);
    if (device == null || device.isEmpty) {
      // Persist before publishing: a failed vault write must never register a key.
      await _writeDevice(await _newDevice());
    } else {
      final raw = jsonDecode(device) as Map;
      _device = await _deviceFrom(raw['device_id'] as String,
          raw['exchange_private'] as String, raw['signing_private'] as String);
      _linkAccountKey = raw['link_account_signing_key'] as String?;
    }
    final staged = await store.read(_approvalKey);
    _staged =
        staged == null || staged.isEmpty ? null : await _parseKeyring(staged);
    final floor = await store.read(_floorKey);
    if (floor != null && floor.isNotEmpty) {
      final data = jsonDecode(floor) as Map;
      _floorVersion = data['version'] as int? ?? 0;
      for (final e in (data['revoked'] as Map? ?? const {}).entries) {
        _floorRevoked[e.key as String] =
            (e.value as Map).cast<String, dynamic>();
      }
    }
    await _reloadTrust();
  }

  Future<void> _reloadTrust() async {
    final trust = await store.read(_trustKey);
    if (trust == null || trust.isEmpty) return;
    for (final e in (jsonDecode(trust) as Map).entries) {
      _trusted[e.key as String] =
          _normalizePin((e.value as Map).cast<String, dynamic>());
    }
  }

  /// v1 pins hold just the identity, which was always account version 1.
  static Map<String, dynamic> _normalizePin(Map<String, dynamic> pin) {
    final version = pin['version'] as int? ?? 1;
    return {
      'version': version,
      'exchange_key': pin['exchange_key'],
      'signing_key': pin['signing_key'],
      'accounts': pin['accounts'] ??
          [
            {
              'version': version,
              'exchange_key': pin['exchange_key'],
              'signing_key': pin['signing_key'],
            }
          ],
      'devices': pin['devices'] ?? <String, dynamic>{},
    };
  }

  Future<void> _raiseFloor(int version,
      [Map<String, Map<String, dynamic>> revoked = const {}]) async {
    final added = revoked.keys.any((id) => !_floorRevoked.containsKey(id));
    if (version <= _floorVersion && !added) return;
    _floorVersion = max(_floorVersion, version);
    _floorRevoked.addAll(revoked);
    await store.write(_floorKey,
        jsonEncode({'version': _floorVersion, 'revoked': _floorRevoked}));
  }

  bool get _holdsKeyring => _confirmed && _keyring.isNotEmpty;

  Future<void> _register({bool renewed = false, bool refreshed = false}) async {
    var state = await _fetchState();
    var account = _map(state['account']);
    if (account == null) {
      if (_keyring.isEmpty) {
        await _writeKeyring([await _newAccount(1)], confirmed: false);
      }
      if (_keyring.length != 1 ||
          _keyring.single.version != 1 ||
          _floorVersion > 1) {
        // The server lost (or hides) an account this device already held.
        return _block();
      }
      final result =
          await rest.makeRequest('PUT', '/users/@me/encryption', body: {
        'exchange_key': _keyring.single.exchangeKey,
        'signing_key': _keyring.single.signingKey,
      });
      if (result.statusCode == 409) {
        // Another device created the account first: this one waits for approval.
        state = await _fetchState();
        account = _map(state['account']);
      } else if (!result.ok) {
        throw EncryptionException(result.error?.message ??
            'Unable to set up private chat encryption.');
      } else {
        account = _keyring.single.public;
      }
      if (account == null) {
        throw const EncryptionException(
            'Unable to set up private chat encryption.');
      }
    }
    await _commitStagedRotation(account);
    if (_holdsKeyring) {
      return _registerHolder(state, account, refreshed: refreshed);
    }
    if (_staged == null && _isCurrent(account)) {
      // A new account, or a migrated v1 identity the server holds.
      final result = await _putDevice(certifyWith: _keyring.last);
      if (result.statusCode == 409 && !refreshed) {
        return _register(renewed: renewed, refreshed: true);
      }
      if (result.ok) {
        await _writeKeyring(_keyring);
        await _raiseFloor(_keyring.last.version);
        await _setLinkKey(null);
        _setSetup(PrivateChatSetup.active);
        return;
      }
      if (result.statusCode != 403) _refuse(result);
    }
    return _registerPending(state, account, renewed: renewed, put: true);
  }

  /// A device holding the account keyring never goes back to pending: it is
  /// active on its newest version, follows a verified rotation, or is blocked.
  Future<void> _registerHolder(
      Map<String, dynamic> state, Map<String, dynamic> account,
      {bool refreshed = false, bool put = true}) async {
    final version = account['version'] as int? ?? 1;
    if (version < _floorVersion || version < _keyring.last.version) {
      return _block();
    }
    if (_isCurrent(account)) {
      if (put) {
        final result = await _putDevice(certifyWith: _keyring.last);
        if (result.statusCode == 409 && !refreshed) {
          return _register(refreshed: true);
        }
        // This device was removed.
        if (result.statusCode == 403) return _block();
        _refuse(result);
      }
      await _raiseFloor(_keyring.last.version);
      _setSetup(PrivateChatSetup.active);
      return;
    }
    if (version > _keyring.last.version && await _followRotation(state)) {
      _setSetup(PrivateChatSetup.active);
      return;
    }
    _block();
  }

  /// Pending (or approved, awaiting confirmation) devices.
  Future<void> _registerPending(
      Map<String, dynamic> state, Map<String, dynamic> account,
      {bool renewed = false, required bool put}) async {
    final own = _ownRow(state);
    var force = renewed || own == null;
    if (_staged == null && _linkAccountKey != account['signing_key']) {
      // The code must use the account key the server shows now: re-register.
      force = force || _linkAccountKey != null;
      put = true;
      await _setLinkKey(account['signing_key'] as String);
    }
    var status = own?['status'];
    if (put || own == null) {
      final result = await _putDevice();
      if (result.statusCode == 403 && !renewed) {
        // This device id was removed; it can only come back as a new device.
        await _writeDevice(await _newDevice());
        return _registerPending(state, account, renewed: true, put: true);
      }
      _refuse(result);
      status = _map(result.data)?['status'];
    }
    if (_staged != null) {
      _setSetup(PrivateChatSetup.approved);
      return;
    }
    if (status == 'active') {
      // Approved while we were away. A bad package must not fail startup:
      // that would re-run registration on every decrypt.
      try {
        if (await _acceptApproval()) {
          _setSetup(PrivateChatSetup.approved);
          return;
        }
      } catch (_) {}
    }
    _setSetup(PrivateChatSetup.pending, force: force);
  }

  void _refuse(RestResult result) {
    if (result.ok) return;
    final message =
        result.error?.message ?? 'Unable to set up private chat encryption.';
    final status = result.statusCode;
    if (status >= 400 && status < 500 && status != 408 && status != 429) {
      throw _RegistrationRefused(message);
    }
    throw EncryptionException(message);
  }

  Map<String, dynamic>? _ownRow(Map<String, dynamic> state) =>
      _rows(state).where((r) => r['device_id'] == _device!.id).firstOrNull;

  Future<Map<String, dynamic>> _fetchState() async {
    final result = await rest.makeRequest('GET', '/users/@me/encryption');
    if (!result.ok || result.data is! Map) {
      throw EncryptionException(
          result.error?.message ?? 'Unable to load encryption devices.');
    }
    final state = (result.data as Map).cast<String, dynamic>();
    _userContext = state['user_context'] as String? ?? userId;
    return state;
  }

  /// Registers this device. `binding` proves possession of the device key for
  /// this session: `["daccord-e2ee-bind-v2", user, device, b64(SHA-256(token))]`.
  Future<RestResult> _putDevice({_Account? certifyWith}) async {
    final d = _device!;
    final token =
        base64Encode((await Sha256().hash(utf8.encode(rest.token))).bytes);
    final binding = await _signing.sign(
        _json(['daccord-e2ee-bind-v2', _context, d.id, token]),
        keyPair: d.signing);
    return rest
        .makeRequest('PUT', '/users/@me/encryption/devices/${d.id}', body: {
      'name': deviceName,
      'exchange_key': d.exchangeKey,
      'signing_key': d.signingKey,
      'binding': base64Encode(binding.bytes),
      if (certifyWith != null) ...{
        'certificate':
            await _certify(certifyWith, d.id, d.exchangeKey, d.signingKey),
        'account_version': certifyWith.version,
      },
    });
  }

  /// Whether the server's account is our newest keyring version.
  bool _isCurrent(Map<String, dynamic>? account) =>
      account != null &&
      _keyring.isNotEmpty &&
      _keyring.last.version == (account['version'] as int? ?? 1) &&
      _keyring.last.exchangeKey == account['exchange_key'] &&
      _keyring.last.signingKey == account['signing_key'];

  // ── Vault ─────────────────────────────────────────────────────────────────

  static Future<_Account> _accountFrom(
      int version, String exchangePrivate, String signingPrivate) async {
    final x = await _exchange.newKeyPairFromSeed(_seed(exchangePrivate));
    final s = await _signing.newKeyPairFromSeed(_seed(signingPrivate));
    return _Account(
        version,
        x,
        s,
        base64Encode((await x.extractPublicKey()).bytes),
        base64Encode((await s.extractPublicKey()).bytes),
        exchangePrivate,
        signingPrivate);
  }

  static Future<_Account> _newAccount(int version) async => _accountFrom(
      version, base64Encode(_random(32)), base64Encode(_random(32)));

  static Future<_Device> _deviceFrom(
      String id, String exchangePrivate, String signingPrivate) async {
    if (!_deviceIdPattern.hasMatch(id)) {
      throw const EncryptionException('Invalid encryption device id.');
    }
    final x = await _exchange.newKeyPairFromSeed(_seed(exchangePrivate));
    final s = await _signing.newKeyPairFromSeed(_seed(signingPrivate));
    return _Device(
        id,
        x,
        s,
        base64Encode((await x.extractPublicKey()).bytes),
        base64Encode((await s.extractPublicKey()).bytes),
        exchangePrivate,
        signingPrivate);
  }

  static Future<_Device> _newDevice() => _deviceFrom(
      base64Url.encode(_random(16)).replaceAll('=', ''),
      base64Encode(_random(32)),
      base64Encode(_random(32)));

  static List<int> _seed(String encoded) {
    final bytes = base64Decode(encoded);
    if (bytes.length != 32) {
      throw const EncryptionException('Invalid encryption key.');
    }
    return bytes;
  }

  static Future<List<_Account>> _parseKeyring(String raw) async {
    final data = jsonDecode(raw);
    final accounts = data is Map ? data['accounts'] : null;
    if (accounts is! List || accounts.isEmpty || accounts.length > 1000) {
      throw const EncryptionException('Invalid encryption keyring.');
    }
    final out = <_Account>[];
    for (final entry in accounts) {
      final version = entry is Map ? entry['version'] : null;
      if (version is! int ||
          version < 1 ||
          (out.isNotEmpty && version <= out.last.version)) {
        throw const EncryptionException('Invalid encryption keyring.');
      }
      out.add(await _accountFrom(version, entry['exchange_private'] as String,
          entry['signing_private'] as String));
    }
    return out;
  }

  static String _keyringJson(List<_Account> keyring) => jsonEncode({
        'accounts': [for (final a in keyring) a.secret]
      });

  Future<void> _writeKeyring(List<_Account> keyring,
      {bool confirmed = true}) async {
    await store.write(
        _keyringKey,
        jsonEncode({
          'accounts': [for (final a in keyring) a.secret],
          'confirmed': confirmed,
        }));
    _keyring = keyring;
    _confirmed = confirmed;
  }

  Future<void> _writeDevice(_Device device, {String? linkKey}) async {
    await store.write(
        _deviceKey,
        jsonEncode({
          'device_id': device.id,
          'exchange_private': device.exchangePrivate,
          'signing_private': device.signingPrivate,
          if (linkKey != null) 'link_account_signing_key': linkKey,
        }));
    _device = device;
    _linkAccountKey = linkKey;
  }

  Future<void> _setLinkKey(String? key) async {
    if (_linkAccountKey == key) return;
    await _writeDevice(_device!, linkKey: key);
  }

  Future<void> _setStaged(List<_Account>? keyring) async {
    await store.write(
        _approvalKey, keyring == null ? '' : _keyringJson(keyring));
    _staged = keyring;
  }

  /// A rotation is staged before it is sent, so a crash or a lost response
  /// after the server accepted it cannot lose the new private key.
  Future<void> _commitStagedRotation(Map<String, dynamic> account) async {
    final raw = await store.read(_rotationKey);
    if (raw == null || raw.isEmpty) return;
    final staged = (await _parseKeyring(raw)).single;
    if (staged.version == account['version'] &&
        staged.exchangeKey == account['exchange_key'] &&
        staged.signingKey == account['signing_key'] &&
        _holdsKeyring &&
        staged.version == _keyring.last.version + 1) {
      await _writeKeyring([..._keyring, staged]);
      final revoked = (jsonDecode(raw) as Map)['revoke'] as Map? ?? const {};
      await _raiseFloor(staged.version, {
        for (final e in revoked.entries)
          e.key as String: (e.value as Map).cast<String, dynamic>()
      });
    }
    await store.write(_rotationKey, '');
  }

  // ── Certificates, codes and key packages ──────────────────────────────────

  static List<int> _certificateMessage(String userContext, int version,
          String deviceId, String exchangeKey, String signingKey) =>
      _json([
        'daccord-e2ee-device-v2',
        userContext,
        version,
        deviceId,
        exchangeKey,
        signingKey
      ]);

  static List<int> _successionMessage(String userContext, int version,
          String exchangeKey, String signingKey) =>
      _json([
        'daccord-e2ee-rotate-v2',
        userContext,
        version,
        exchangeKey,
        signingKey
      ]);

  /// Signed by the NEW key of [version] over the previous version's keys.
  static List<int> _backMessage(String userContext, int version,
          String previousExchangeKey, String previousSigningKey) =>
      _json([
        'daccord-e2ee-rotate-back-v2',
        userContext,
        version,
        previousExchangeKey,
        previousSigningKey
      ]);

  Future<String> _certify(_Account account, String deviceId, String exchangeKey,
      String signingKey) async {
    final signature = await _signing.sign(
        _certificateMessage(
            _context, account.version, deviceId, exchangeKey, signingKey),
        keyPair: account.signing);
    return base64Encode(signature.bytes);
  }

  static Future<bool> _verify(
      List<int> message, Object? signature, Object? publicKey) async {
    if (signature is! String || publicKey is! String) return false;
    try {
      final bytes = base64Decode(signature);
      final key = base64Decode(publicKey);
      if (bytes.length != 64 || key.length != 32) return false;
      return await _signing.verify(message,
          signature: Signature(bytes,
              publicKey: SimplePublicKey(key, type: KeyPairType.ed25519)));
    } catch (_) {
      return false;
    }
  }

  /// A succession [entry] (version v) links to [previous] (version v - 1)
  /// only when signed in both directions: forward by the old key and back by
  /// the new one.
  static Future<bool> _verifyLink(String user, Map<String, dynamic> entry,
      Map<String, dynamic> previous) async {
    final version = entry['version'];
    if (version is! int || !_validKeys(entry) || !_validKeys(previous)) {
      return false;
    }
    return await _verify(
            _successionMessage(user, version, entry['exchange_key'] as String,
                entry['signing_key'] as String),
            entry['signature'],
            previous['signing_key']) &&
        await _verify(
            _backMessage(user, version, previous['exchange_key'] as String,
                previous['signing_key'] as String),
            entry['back_signature'],
            entry['signing_key']);
  }

  static Future<String> _code(String userContext, String accountSigningKey,
      String deviceId, String exchangeKey, String signingKey) async {
    final digest = (await Sha256().hash(_json([
      'daccord-e2ee-link-v2',
      userContext,
      accountSigningKey,
      deviceId,
      exchangeKey,
      signingKey
    ])))
        .bytes;
    var n = BigInt.zero;
    for (var i = 0; i < 8; i++) {
      n = (n << 8) | BigInt.from(digest[i]);
    }
    final code = (n % BigInt.from(10).pow(16)).toString().padLeft(16, '0');
    return [for (var i = 0; i < 16; i += 4) code.substring(i, i + 4)].join(' ');
  }

  List<int> _packageInfo(
          String deviceId, String deviceExchangeKey, String ephemeral) =>
      _json([
        'daccord-e2ee-package-v2',
        _context,
        deviceId,
        deviceExchangeKey,
        ephemeral
      ]);

  Future<String> _sealPackage(
      String deviceId, String deviceExchangeKey, List<_Account> keyring) async {
    final ephemeral = await _exchange.newKeyPair();
    final public = base64Encode((await ephemeral.extractPublicKey()).bytes);
    final info = _packageInfo(deviceId, deviceExchangeKey, public);
    final key = await _derive(ephemeral, deviceExchangeKey, info);
    final package = jsonEncode({
      'ephemeral': public,
      'box': await _seal(utf8.encode(_keyringJson(keyring)), key, info),
    });
    if (utf8.encode(package).length > 16 * 1024) {
      throw const EncryptionException('Encryption keyring is too large.');
    }
    return package;
  }

  /// This device's key package, opened; null when there is none.
  Future<List<_Account>?> _fetchPackage() async {
    final d = _device!;
    final result = await rest.makeRequest(
        'GET', '/users/@me/encryption/devices/${d.id}/package');
    if (result.statusCode == 404) return null;
    if (!result.ok || result.data is! Map) {
      throw EncryptionException(
          result.error?.message ?? 'Unable to fetch this device’s keys.');
    }
    final encoded = (result.data as Map)['key_package'];
    if (encoded is! String || utf8.encode(encoded).length > 16 * 1024) {
      throw const EncryptionException('Invalid approval package.');
    }
    final data = jsonDecode(encoded);
    if (data is! Map ||
        data['ephemeral'] is! String ||
        data['box'] is! String) {
      throw const EncryptionException('Invalid approval package.');
    }
    final ephemeral = _key(data['ephemeral'], exchange: true);
    final info = _packageInfo(d.id, d.exchangeKey, ephemeral);
    final key = await _derive(d.exchange, ephemeral, info);
    return _parseKeyring(
        utf8.decode(await _open(data['box'] as String, key, info)));
  }

  /// Acknowledging only deletes the server copy; a failure is harmless.
  Future<void> _ackPackage() async {
    try {
      await rest.makeRequest(
          'DELETE', '/users/@me/encryption/devices/${_device!.id}/package');
    } catch (_) {}
  }

  /// Pending device: stage an approval package whose current account key is
  /// the one this device's link code was computed from. It only becomes
  /// usable after the user confirms the codes matched ([confirmApproval]).
  Future<bool> _acceptApproval() async {
    final package = await _fetchPackage();
    if (package == null) return false;
    if (_linkAccountKey == null || package.last.signingKey != _linkAccountKey) {
      throw const EncryptionException(
          'The approval package does not match this device’s link code.');
    }
    await _setStaged(package);
    await _ackPackage();
    return true;
  }

  /// Active device: another device rotated the account key. Accept the new
  /// versions only when they chain from our newest one through successions
  /// signed in both directions, and only from our package; existing keyring
  /// versions are never replaced.
  Future<bool> _followRotation(Map<String, dynamic> state) async {
    final account = _map(state['account']);
    if (account == null || !_holdsKeyring) return false;
    final version = account['version'] as int? ?? 1;
    final successions = _successions(state);
    final chain = <int, Map<String, dynamic>>{
      _keyring.last.version: _keyring.last.public
    };
    for (var v = _keyring.last.version + 1; v <= version; v++) {
      final s = successions[v];
      if (s == null || !await _verifyLink(_context, s, chain[v - 1]!)) {
        return false;
      }
      chain[v] = s;
    }
    if (!_sameKeys(chain[version], account)) return false;
    if (_ownRow(state)?['status'] != 'active') return false;
    // Re-bind this session to the device so the package can be fetched.
    if (!(await _putDevice()).ok) return false;
    final List<_Account>? package;
    try {
      package = await _fetchPackage();
    } on EncryptionException {
      return false;
    }
    if (package == null) return false;
    final held = {for (final a in _keyring) a.version: a};
    final added = <_Account>[];
    for (final a in package) {
      final mine = held[a.version];
      if (mine != null) {
        if (!mine.sameAs(a)) return false;
      } else if (a.version > _keyring.last.version && a.version <= version) {
        if (!_sameKeys(chain[a.version], a.public)) return false;
        added.add(a);
      } else {
        return false;
      }
    }
    if (added.length != version - _keyring.last.version) return false;
    await _writeKeyring([..._keyring, ...added]);
    await _ackPackage();
    await _raiseFloor(version);
    return true;
  }

  static Map<int, Map<String, dynamic>> _successions(
      Map<String, dynamic>? row) {
    final out = <int, Map<String, dynamic>>{};
    for (final raw in row?['successions'] as List? ?? const []) {
      if (raw is Map && raw['version'] is int) {
        out[raw['version'] as int] = raw.cast<String, dynamic>();
      }
    }
    return out;
  }

  // ── Devices ───────────────────────────────────────────────────────────────

  void _requireActive() {
    switch (_setup) {
      case PrivateChatSetup.blocked:
        throw const EncryptionException(blockedMessage);
      case PrivateChatSetup.pending:
      case PrivateChatSetup.approved:
        throw const EncryptionException(pendingMessage);
      case PrivateChatSetup.active when _keyring.isNotEmpty:
        return;
      default:
        throw const EncryptionException(
            'Private chat encryption is not set up on this device.');
    }
  }

  /// This device's link code, to compare with the one an approving device
  /// shows for it. While pending it always uses the account key fixed at
  /// registration; re-read it whenever [setupChanges] emits `pending`.
  Future<String> linkCode() async {
    await initialize();
    final d = _device!;
    final accountKey = _setup == PrivateChatSetup.active
        ? _keyring.last.signingKey
        : _linkAccountKey ??
            _map((await _fetchState())['account'])?['signing_key'] as String?;
    if (accountKey == null) {
      throw const EncryptionException(
          'This account has no encryption keys yet.');
    }
    return _code(_context, accountKey, d.id, d.exchangeKey, d.signingKey);
  }

  /// The link code an approver shows for [device]. Remembers the compared
  /// keys: [approveDevice] refuses a device whose code was not computed here,
  /// or whose keys changed since.
  Future<String> linkCodeFor(EncryptionDevice device) async {
    await initialize();
    _requireActive();
    if (!_deviceIdPattern.hasMatch(device.deviceId)) {
      throw const EncryptionException('Invalid encryption device id.');
    }
    final exchangeKey = _key(device.exchangeKey, exchange: true);
    final signingKey = _key(device.signingKey);
    final accountKey = _keyring.last.signingKey;
    _compared[device.deviceId] = (
      exchangeKey: exchangeKey,
      signingKey: signingKey,
      accountKey: accountKey
    );
    return _code(
        _context, accountKey, device.deviceId, exchangeKey, signingKey);
  }

  /// The user confirmed on this device that the approving device showed the
  /// same link code: install the approved keyring and become active.
  Future<void> confirmApproval() async {
    await initialize();
    await _serialized(() async {
      final staged = _staged;
      if (_setup != PrivateChatSetup.approved || staged == null) {
        throw const EncryptionException(
            'There is no approval to confirm on this device.');
      }
      // Any local keyring here is an unconfirmed (never accepted) v1
      // identity; the approved keyring replaces it.
      await _writeKeyring(staged);
      await _setStaged(null);
      await _setLinkKey(null);
      await _raiseFloor(staged.last.version);
      _setSetup(PrivateChatSetup.active);
    });
  }

  /// The codes did not match: discard the approval, decline the device and
  /// register again as a new pending device (with a new link code).
  Future<void> rejectApproval() async {
    await initialize();
    await _serialized(() async {
      if (_setup != PrivateChatSetup.approved) {
        throw const EncryptionException(
            'There is no approval to reject on this device.');
      }
      await _setStaged(null);
      try {
        await rest.makeRequest(
            'DELETE', '/users/@me/encryption/devices/${_device!.id}');
      } catch (_) {}
      await _writeDevice(await _newDevice());
      final state = await _fetchState();
      final account = _map(state['account']);
      if (account == null) {
        throw const EncryptionException(
            'This account has no encryption keys yet.');
      }
      await _registerPending(state, account, renewed: true, put: true);
    });
  }

  Future<List<EncryptionDevice>> listDevices() async {
    await initialize();
    final state = await _fetchState();
    return [
      for (final raw in state['devices'] as List? ?? const [])
        EncryptionDevice.fromJson((raw as Map).cast<String, dynamic>(),
            currentDeviceId: _device?.id)
    ];
  }

  /// Our keyring must hold the server's current account version. Follows a
  /// verified rotation by another device; anything else blocks.
  Future<void> _requireCurrent(Map<String, dynamic> state) async {
    final account = _map(state['account']);
    if (account == null) throw const EncryptionException(blockedMessage);
    if (_isCurrent(account)) return;
    await _registerHolder(state, account, put: false);
    if (!_isCurrent(account)) throw const EncryptionException(blockedMessage);
  }

  static List<Map<String, dynamic>> _rows(Map<String, dynamic> state) => [
        for (final raw in state['devices'] as List? ?? const [])
          if (raw is Map) raw.cast<String, dynamic>()
      ];

  /// Certifies a pending device and seals the keyring to it. Call
  /// [linkCodeFor] first and let the user confirm both codes match; the new
  /// device asks its user to confirm too.
  Future<void> approveDevice(String deviceId) async {
    await initialize();
    _requireActive();
    final compared = _compared[deviceId];
    if (compared == null) {
      throw const EncryptionException(
          'Compare the link code with the new device before approving it.');
    }
    await _serialized(() async {
      final state = await _fetchState();
      await _requireCurrent(state);
      final row = _rows(state).where((r) => r['device_id'] == deviceId);
      if (row.isEmpty || row.first['status'] != 'pending') {
        throw const EncryptionException(
            'This device is no longer waiting for approval.');
      }
      final account = _keyring.last;
      if (row.first['exchange_key'] != compared.exchangeKey ||
          row.first['signing_key'] != compared.signingKey ||
          compared.accountKey != account.signingKey) {
        throw const EncryptionException(
            'This device’s link code changed. Compare the codes again.');
      }
      final result = await rest.makeRequest(
          'POST', '/users/@me/encryption/devices/$deviceId/approve',
          body: {
            'certificate': await _certify(
                account, deviceId, compared.exchangeKey, compared.signingKey),
            'account_version': account.version,
            'key_package':
                await _sealPackage(deviceId, compared.exchangeKey, _keyring),
          });
      if (!result.ok) {
        throw EncryptionException(
            result.error?.message ?? 'Unable to approve this device.');
      }
    });
    _compared.remove(deviceId);
  }

  /// Declines a pending device (no rotation needed: it never held keys).
  Future<void> declineDevice(String deviceId) async {
    final result = await rest.makeRequest(
        'DELETE', '/users/@me/encryption/devices/$deviceId');
    if (!result.ok) {
      throw EncryptionException(
          result.error?.message ?? 'Unable to decline this device.');
    }
    _compared.remove(deviceId);
  }

  /// Removes active devices by rotating the account key: they cannot read
  /// later messages, but keep whatever they already had. Pending devices are
  /// discarded by the rotation too. This device cannot remove itself.
  Future<void> removeDevices(List<String> deviceIds) async {
    await initialize();
    _requireActive();
    if (deviceIds.isEmpty) return;
    final d = _device!;
    if (deviceIds.contains(d.id)) {
      throw const EncryptionException(
          'Remove this device from another of your devices.');
    }
    await _serialized(() async {
      final state = await _fetchState();
      await _requireCurrent(state);
      final current = _keyring.last;
      final rows = _rows(state);
      final revoke = <String>[];
      for (final id in deviceIds.toSet()) {
        final row = rows.where((r) => r['device_id'] == id);
        if (row.isEmpty) {
          throw const EncryptionException('Unknown encryption device.');
        }
        if (row.first['status'] == 'active') revoke.add(id);
      }
      final remaining = [
        for (final r in rows)
          if (r['status'] == 'active' && !revoke.contains(r['device_id'])) r
      ];
      if (!remaining.any((r) => r['device_id'] == d.id)) {
        throw const EncryptionException(
            'This device is not active for encrypted chats.');
      }
      // Never certify or seal keys to a device the account did not approve
      // for its current key, or to one this device has seen removed.
      for (final r in remaining) {
        final id = r['device_id'];
        if (id is! String ||
            !_deviceIdPattern.hasMatch(id) ||
            _floorRevoked.containsKey(id) ||
            r['account_version'] != current.version ||
            !_validKeys(r) ||
            !await _verify(
                _certificateMessage(_context, current.version, id,
                    r['exchange_key'] as String, r['signing_key'] as String),
                r['certificate'],
                current.signingKey)) {
          throw const EncryptionException(
              'A device has an invalid certificate. Removal was cancelled.');
        }
      }
      final revoked = {
        for (final r in rows)
          if (revoke.contains(r['device_id']))
            r['device_id'] as String: {
              'exchange_key': r['exchange_key'],
              'signing_key': r['signing_key'],
            }
      };
      final next = await _newAccount(current.version + 1);
      final keyring = [..._keyring, next];
      await store.write(
          _rotationKey,
          jsonEncode({
            'accounts': [next.secret],
            'revoke': revoked,
          }));
      final signature = await _signing.sign(
          _successionMessage(
              _context, next.version, next.exchangeKey, next.signingKey),
          keyPair: current.signing);
      final backSignature = await _signing.sign(
          _backMessage(
              _context, next.version, current.exchangeKey, current.signingKey),
          keyPair: next.signing);
      final result =
          await rest.makeRequest('POST', '/users/@me/encryption/rotate', body: {
        'revoke': revoke,
        'account': {
          'exchange_key': next.exchangeKey,
          'signing_key': next.signingKey,
        },
        'version': next.version,
        'signature': base64Encode(signature.bytes),
        'back_signature': base64Encode(backSignature.bytes),
        'devices': [
          for (final r in remaining)
            {
              'device_id': r['device_id'],
              'certificate': await _certify(next, r['device_id'] as String,
                  r['exchange_key'] as String, r['signing_key'] as String),
            }
        ],
        'packages': [
          for (final r in remaining)
            if (r['device_id'] != d.id)
              {
                'device_id': r['device_id'],
                'key_package': await _sealPackage(r['device_id'] as String,
                    r['exchange_key'] as String, keyring),
              }
        ],
      });
      if (!result.ok) {
        final status = result.statusCode;
        if (status >= 400 && status < 500 && status != 408 && status != 429) {
          // Definitely refused: the staged key is not the account's.
          await store.write(_rotationKey, '');
          throw EncryptionException(
              result.error?.message ?? 'Unable to remove these devices.');
        }
        // The server may have applied it; the staged key is committed (or
        // discarded) once the server's state is known.
        throw EncryptionException(result.error?.message ??
            'Removing these devices did not finish. Daccord will check again when it reconnects.');
      }
      await _writeKeyring(keyring);
      await store.write(_rotationKey, '');
      await _raiseFloor(next.version, revoked);
    });
  }

  /// Pending: checks whether another device approved this one (the result
  /// then waits for [confirmApproval]); re-registers if it was declined or
  /// expired, or the account key changed (new link code). Active: follows a
  /// rotation by another device. Blocked: re-checks the server's keys.
  /// Returns true once this device is active on the current account key.
  Future<bool> checkApproval() async {
    await initialize();
    return _serialized(() async {
      final state = await _fetchState();
      final account = _map(state['account']);
      if (account == null || _device == null) return false;
      await _commitStagedRotation(account);
      switch (_setup) {
        case PrivateChatSetup.active:
        case PrivateChatSetup.blocked:
          if (!_holdsKeyring) return false;
          await _registerHolder(state, account, put: false);
          return _setup == PrivateChatSetup.active;
        case PrivateChatSetup.pending:
          await _registerPending(state, account, put: false);
          return false;
        case PrivateChatSetup.approved:
        case PrivateChatSetup.unknown:
          return false;
      }
    });
  }

  // ── Discovery and trust ───────────────────────────────────────────────────

  /// Current participants keyed by wire user id. Each value holds the current
  /// account `exchange_key`/`signing_key`/`version` plus the verified
  /// `accounts` chain and `devices` (certificate-checked).
  Future<Map<String, Map<String, dynamic>>> participants(String channelId,
      {bool requireReady = true}) async {
    await initialize();
    if (_setup == PrivateChatSetup.blocked) {
      throw const EncryptionException(blockedMessage);
    }
    final result =
        await rest.makeRequest('GET', '/channels/$channelId/encryption');
    if (!result.ok) {
      throw EncryptionException(
          result.error?.message ?? 'Unable to fetch encryption keys.');
    }
    final discovery = (result.data as Map).cast<String, dynamic>();
    final wireChannel = discovery['channel_id'] as String;
    if (wireChannel != channelId &&
        (channelId.contains('@') || !wireChannel.startsWith('$channelId@'))) {
      throw const EncryptionException(
          'Encryption discovery returned another chat.');
    }
    _channels[channelId] = wireChannel;
    _selves[channelId] = discovery['self_user_id'] as String;
    if (discovery['cdn_url'] is String) {
      _cdns[channelId] = discovery['cdn_url'] as String;
    }
    final rows = discovery['participants'] as List;
    final aliases = <String, String>{};
    final found = <String, Map<String, dynamic>>{};
    for (final raw in rows) {
      final row = (raw as Map).cast<String, dynamic>();
      if (row['identity'] == null) {
        if (requireReady && row['current'] != false) {
          throw const EncryptionException(
              'Every participant must open an updated Daccord client to set up encryption.');
        }
        continue;
      }
      aliases[row['user_id'] as String] = row['wire_user_id'] as String;
      found[row['wire_user_id'] as String] = row;
    }
    _aliases[channelId] = aliases;
    final self = _selves[channelId]!;
    if (_setup == PrivateChatSetup.active) {
      final mine = found[self] == null ? null : _rowAccount(found[self]!);
      if (!_isCurrent(mine)) {
        if (mine != null && (mine['version'] as int) > _keyring.last.version) {
          await checkApproval();
        }
        // Never fall back to an older or unknown own key (no rollback).
        if (_setup != PrivateChatSetup.active || !_isCurrent(mine)) {
          throw const EncryptionException(blockedMessage);
        }
      }
    }
    // Serialize with the vault's other updates and persist TOFU before use.
    final keys = await _serialized(() async {
      await _reloadTrust();
      final resolved = <String, Map<String, dynamic>>{};
      for (final e in found.entries) {
        resolved[e.key] = await _resolve(e.key, e.value,
            own: e.key == self && _setup == PrivateChatSetup.active);
      }
      final next = {
        ..._trusted,
        for (final e in resolved.entries)
          e.key: {
            for (final f in e.value.entries)
              if (f.key != 'active_devices' && f.key != 'invalid_devices')
                f.key: f.value
          }
      };
      await store.write(_trustKey, jsonEncode(next));
      _trusted.addAll(next);
      return resolved;
    });
    if (requireReady) {
      final current = <String>{
        for (final row in rows)
          if ((row as Map)['current'] != false) row['wire_user_id'] as String
      };
      keys.removeWhere((id, _) => !current.contains(id));
    }
    return keys;
  }

  static Map<String, dynamic>? _rowAccount(Map<String, dynamic> row) {
    final identity = row['identity'];
    if (identity is! Map) return null;
    return {
      'version': row['account_version'] as int? ?? 1,
      'exchange_key': identity['exchange_key'],
      'signing_key': identity['signing_key'],
    };
  }

  static bool _sameKeys(Map<String, dynamic>? a, Map<String, dynamic>? b) =>
      a != null &&
      b != null &&
      a['exchange_key'] == b['exchange_key'] &&
      a['signing_key'] == b['signing_key'];

  /// Verifies a participant's account versions: the pin (or, on first sight,
  /// the current key), forward through successions signed in both
  /// directions, and backward only through back-signatures from the oldest
  /// trusted version. Unauthenticated older versions are ignored. Then checks
  /// each device certificate.
  Future<Map<String, dynamic>> _resolve(String user, Map<String, dynamic> row,
      {required bool own}) async {
    final changed = EncryptionException(
        'Encryption identity changed for $user. Sending and decryption are blocked.');
    final current = _rowAccount(row)!;
    final version = current['version'] as int;
    if (!_validKeys(current)) throw changed;
    final successions = _successions(row);
    final known = <int, Map<String, dynamic>>{};
    final pin = _trusted[user];
    if (own) {
      for (final a in _keyring) {
        known[a.version] = a.public;
      }
    } else if (pin == null) {
      known[version] = current; // Trust on first use, as v1.
    } else {
      for (final a in pin['accounts'] as List) {
        known[(a as Map)['version'] as int] = a.cast<String, dynamic>();
      }
      final pinned = pin['version'] as int;
      if (version < pinned) throw changed;
      for (final e in successions.entries) {
        if (known[e.key] != null && !_sameKeys(known[e.key], e.value)) {
          throw changed;
        }
      }
      for (var v = pinned + 1; v <= version; v++) {
        final s = successions[v];
        if (s == null || !await _verifyLink(user, s, known[v - 1]!)) {
          throw changed;
        }
        known[v] = s;
      }
    }
    if (!_sameKeys(known[version], current) ||
        successions.keys.any((v) => v > version)) {
      throw changed;
    }
    if (!own) {
      var oldest = known.keys.reduce(min);
      while (oldest > 1) {
        final link = successions[oldest];
        final older = successions[oldest - 1];
        if (link == null ||
            older == null ||
            !_sameKeys(link, known[oldest]) ||
            !await _verifyLink(user, link, older)) {
          break;
        }
        oldest--;
        known[oldest] = older;
      }
    }
    final devices = <String, dynamic>{
      for (final e in (pin?['devices'] as Map? ?? const {}).entries)
        e.key as String: e.value
    };
    final active = <String>[];
    final invalid = <String>[];
    final revokedOwn = <String, Map<String, dynamic>>{};
    // Own devices count only when certified by our newest key and never seen
    // removed; others' when certified by their current version.
    final activeVersion = own ? _keyring.last.version : version;
    for (final raw in row['devices'] as List? ?? const []) {
      if (raw is! Map) continue;
      final revoked = raw['revoked'] == true;
      final id = raw['device_id'];
      try {
        if (id is! String || !_deviceIdPattern.hasMatch(id)) {
          throw const EncryptionException('Invalid device.');
        }
        final exchangeKey = _key(raw['exchange_key'], exchange: true);
        final signingKey = _key(raw['signing_key']);
        final certified = raw['account_version'];
        final previous = devices[id] as Map?;
        if (previous != null &&
            (previous['exchange_key'] != exchangeKey ||
                previous['signing_key'] != signingKey)) {
          throw const EncryptionException('Device keys changed.');
        }
        final signer = certified is int ? known[certified] : null;
        if (signer == null ||
            !await _verify(
                _certificateMessage(
                    user, certified as int, id, exchangeKey, signingKey),
                raw['certificate'],
                signer['signing_key'])) {
          throw const EncryptionException('Invalid device certificate.');
        }
        devices[id] = {
          'exchange_key': exchangeKey,
          'signing_key': signingKey,
          'account_version': certified,
          'certificate': raw['certificate'],
          'revoked': revoked,
        };
        if (own && revoked) {
          revokedOwn[id] = {
            'exchange_key': exchangeKey,
            'signing_key': signingKey
          };
        }
        if (!revoked) {
          final usable = certified == activeVersion &&
              !(own && _floorRevoked.containsKey(id));
          (usable ? active : invalid).add(id);
        }
      } catch (_) {
        if (!revoked) invalid.add(id.toString());
      }
    }
    if (revokedOwn.isNotEmpty) await _raiseFloor(_floorVersion, revokedOwn);
    return {
      'version': version,
      'exchange_key': current['exchange_key'],
      'signing_key': current['signing_key'],
      'accounts': [
        for (final v in known.keys.toList()..sort())
          {
            'version': v,
            'exchange_key': known[v]!['exchange_key'],
            'signing_key': known[v]!['signing_key'],
          }
      ],
      'devices': devices,
      'active_devices': active..sort(),
      'invalid_devices': invalid,
    };
  }

  static bool _validKeys(Map<String, dynamic>? keys) {
    if (keys == null) return false;
    try {
      _key(keys['exchange_key'], exchange: true);
      _key(keys['signing_key']);
      return true;
    } on EncryptionException {
      return false;
    }
  }

  // ── Messages ──────────────────────────────────────────────────────────────

  String? _messageId(String channelId, String? id) {
    if (id == null) return null;
    final channel = _channels[channelId]!;
    final at = channel.indexOf('@');
    return at < 0 || id.contains('@') ? id : '$id${channel.substring(at)}';
  }

  static List<int> _random(int length) {
    final rng = Random.secure();
    return List.generate(length, (_) => rng.nextInt(256));
  }

  static List<int> _json(Object? value) => utf8.encode(jsonEncode(value));

  static Map<String, dynamic>? _map(Object? value) =>
      value is Map ? value.cast<String, dynamic>() : null;

  /// Validates a padded base64 32-byte public key.
  static String _key(Object? value, {bool exchange = false}) {
    if (value is String) {
      try {
        final bytes = base64Decode(value);
        if (bytes.length == 32 &&
            base64Encode(bytes) == value &&
            !(exchange && bytes.every((b) => b == 0))) {
          return value;
        }
      } on FormatException {
        // Reported below.
      }
    }
    throw const EncryptionException('Invalid encryption key.');
  }

  static Future<String> _seal(
      List<int> bytes, SecretKey key, List<int> aad) async {
    final box = await _cipher.encrypt(bytes,
        secretKey: key, nonce: _random(12), aad: aad);
    return base64Encode([...box.nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  static Future<List<int>> _open(
      String encoded, SecretKey key, List<int> aad) async {
    final bytes = base64Decode(encoded);
    if (bytes.length < 28) {
      throw const EncryptionException('Invalid encrypted content.');
    }
    return _cipher.decrypt(
        SecretBox(bytes.sublist(12, bytes.length - 16),
            nonce: bytes.sublist(0, 12),
            mac: Mac(bytes.sublist(bytes.length - 16))),
        secretKey: key,
        aad: aad);
  }

  /// X25519 with [pair] and [remotePublic], then HKDF-SHA256 (empty salt).
  static Future<SecretKey> _derive(
      KeyPair pair, String remotePublic, List<int> info) async {
    final shared = await _exchange.sharedSecretKey(
        keyPair: pair,
        remotePublicKey: SimplePublicKey(base64Decode(remotePublic),
            type: KeyPairType.x25519));
    if ((await shared.extractBytes()).every((v) => v == 0)) {
      throw const EncryptionException('Invalid exchange key.');
    }
    return _hkdf.deriveKey(secretKey: shared, nonce: const [], info: info);
  }

  /// Files and their names/types are sealed before multipart encoding.
  Future<({Map<String, dynamic> data, List<Map<String, dynamic>> files})>
      encrypt(String channelId, Map<String, dynamic> data,
          {List<Map<String, dynamic>> files = const [],
          String? editId,
          Map<String, dynamic>? previousPayload}) async {
    final content = data['content'] as String? ?? '';
    if (utf8.encode(content).length > 4000) {
      throw const EncryptionException(
          'Message content must be at most 4000 bytes.');
    }
    await initialize();
    _requireActive();
    final keys =
        await participants(channelId); // Fresh membership on EVERY send/edit.
    _requireActive();
    final wireChannel = _channels[channelId]!;
    final wireSender = _selves[channelId]!;
    final device = _device!;
    final targets = <List<String>>[];
    for (final e in keys.entries) {
      if ((e.value['invalid_devices'] as List).isNotEmpty) {
        throw EncryptionException(
            'Encryption devices changed for ${e.key}. Sending is blocked.');
      }
      targets.add([e.key, 'account', e.value['exchange_key'] as String]);
      final devices = e.value['devices'] as Map;
      for (final id in e.value['active_devices'] as List) {
        targets.add([
          e.key,
          id as String,
          (devices[id] as Map)['exchange_key'] as String
        ]);
      }
    }
    if (!(keys[wireSender]?['active_devices'] as List? ?? const [])
        .contains(device.id)) {
      throw const EncryptionException(pendingMessage);
    }
    targets.sort((a, b) {
      final user = a[0].compareTo(b[0]);
      return user != 0 ? user : a[1].compareTo(b[1]);
    });
    if (targets.length > 400) {
      throw const EncryptionException(
          'This chat has too many encryption devices.');
    }
    final fileMetadata = <Map<String, dynamic>>[];
    final sealedFiles = <Map<String, dynamic>>[];
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final key = SecretKey(_random(32));
      final bytes = (file['content'] as List<int>);
      final sealed = base64Decode(await _seal(
          bytes, key, _json(['daccord-e2ee-file-v1', wireChannel])));
      fileMetadata.add({
        'filename': file['filename'],
        'content_type': file['content_type'],
        'size': bytes.length,
        'key': base64Encode(await key.extractBytes())
      });
      sealedFiles.add({
        'filename': 'attachment-$i.bin',
        'content_type': 'application/octet-stream',
        'content': Uint8List.fromList(sealed)
      });
    }
    final privatePayload = {
      'content': content,
      'files':
          files.isNotEmpty ? fileMetadata : previousPayload?['files'] ?? [],
      'embeds': data['embeds'] ?? previousPayload?['embeds'] ?? []
    };
    final ephemeral = await _exchange.newKeyPair();
    final p = <dynamic>[
      2,
      wireChannel,
      wireSender,
      device.id,
      base64Encode(_random(16)),
      _messageId(channelId, data['reply_to'] as String?),
      _messageId(channelId, editId),
      base64Encode((await ephemeral.extractPublicKey()).bytes),
      '',
      <dynamic>[],
      _keyring.last.version,
    ];
    final context = _contextV2(p);
    final contentKey = SecretKey(_random(32));
    p[8] = await _seal(_json(privatePayload), contentKey, context);
    if (base64Decode(p[8] as String).length > 64 * 1024) {
      throw const EncryptionException('Encrypted message is too large.');
    }
    final keyBytes = await contentKey.extractBytes();
    for (final t in targets) {
      final wrapping =
          await _derive(ephemeral, t[2], _wrapInfo(context, t[0], t[1], t[2]));
      (p[9] as List).add([
        t[0],
        t[1],
        t[2],
        await _seal(keyBytes, wrapping, _wrapAad(context, t[0], t[1], t[2]))
      ]);
    }
    final signature = await _signing.sign(_json(p), keyPair: device.signing);
    final wire = '$prefixV2${jsonEncode({
          'payload': p,
          'signature': base64Encode(signature.bytes)
        })}';
    if (wire.length > 256 * 1024) {
      throw const EncryptionException('Encrypted message is too large.');
    }
    return (
      data: {
        'content': wire,
        if (data['reply_to'] != null) 'reply_to': data['reply_to']
      },
      files: sealedFiles
    );
  }

  static List<int> _contextV1(List<dynamic> p) =>
      _json(['daccord-e2ee-v1', ...p.sublist(1, 7)]);

  /// `["daccord-e2ee-v2", channel, author, device, token, reply, edit,
  /// ephemeral, account_version]`.
  static List<int> _contextV2(List<dynamic> p) =>
      _json(['daccord-e2ee-v2', ...p.sublist(1, 8), p[10]]);
  static List<int> _wrapInfo(
          List<int> context, String user, String keyId, String public) =>
      _json(
          ['daccord-e2ee-wrap-v2', base64Encode(context), user, keyId, public]);
  static List<int> _wrapAad(
          List<int> context, String user, String keyId, String public) =>
      _json([base64Encode(context), user, keyId, public]);

  Future<AccordMessage> decrypt(AccordMessage message,
      {Map<String, Map<String, dynamic>>? participantKeys,
      Object? discoveryError}) async {
    if (!message.content.startsWith('daccord-e2ee:')) return message;
    // Gateway broadcasts share the raw model. Each consumer owns its decrypted copy.
    message = AccordMessage.fromJson(message.toJson());
    final wire = message.toJson();
    final encoded = message.content;
    // Never surface ciphertext or unverified attachment metadata in the UI.
    message.content = 'Encrypted message unavailable on this device.';
    message.attachments = [];
    message.embeds = [];
    message.encryptedWire = wire;
    try {
      if (discoveryError != null) throw discoveryError;
      if (encoded.length > 256 * 1024) {
        throw const EncryptionException('Encrypted message is too large.');
      }
      final v1 = encoded.startsWith(prefixV1);
      if (!v1 && !encoded.startsWith(prefixV2)) {
        throw const EncryptionException(
            'This encrypted message needs a newer Daccord version.');
      }
      await initialize();
      _requireActive();
      final envelope = jsonDecode(encoded.substring(prefixV1.length)) as Map;
      final p = envelope['payload'] as List;
      final keys = participantKeys ??
          await participants(message.channelId, requireReady: false);
      final payload = v1
          ? await _openV1(message, envelope, p, keys)
          : await _openV2(message, envelope, p, keys,
              refresh: participantKeys == null);
      final attachments = (wire['attachments'] as List)
          .map((a) =>
              AccordAttachment.fromJson((a as Map).cast<String, dynamic>()))
          .toList();
      final metadata = payload['files'] as List;
      if (metadata.length != attachments.length) {
        throw const EncryptionException(
            'Encrypted attachment list is incomplete.');
      }
      for (var i = 0; i < attachments.length; i++) {
        final meta = (metadata[i] as Map).cast<String, dynamic>();
        attachments[i].filename = meta['filename'] as String;
        attachments[i].contentType = meta['content_type'] as String?;
        attachments[i].size = meta['size'] as int;
        attachments[i].encryption = {
          ...meta,
          'channel_id': p[1],
          'cdn_url': _cdns[message.channelId]
        };
      }
      message.content = payload['content'] as String;
      message.attachments = attachments;
      message.privatePayload = payload;
      message.encryptionError = null;
    } catch (e) {
      message.encryptionError = e is EncryptionException
          ? e.message
          : 'Unable to authenticate or decrypt this message.';
      message.content = message.encryptionError!;
    }
    return message;
  }

  void _checkContext(AccordMessage message, List<dynamic> p, int replyIndex) {
    if (p[1] != _channels[message.channelId] ||
        p[2] !=
            (_aliases[message.channelId]?[message.authorId] ??
                message.authorId) ||
        p[replyIndex] != _messageId(message.channelId, message.replyTo) ||
        (p[replyIndex + 1] != null &&
            p[replyIndex + 1] != _messageId(message.channelId, message.id))) {
      throw const EncryptionException('Encrypted message context is invalid.');
    }
  }

  /// Removed authors' pinned identities remain usable for old history.
  Map<String, dynamic> _sender(
      Map<String, Map<String, dynamic>> keys, Object? author) {
    final sender = keys[author] ?? _trusted[author];
    if (sender == null) {
      throw const EncryptionException(
          'Sender encryption identity is unavailable.');
    }
    return sender;
  }

  static bool _knowsVersion(Map<String, dynamic> sender, Object? version) =>
      (sender['accounts'] as List).any((a) => (a as Map)['version'] == version);

  Future<Map<String, dynamic>> _openV1(
      AccordMessage message,
      Map<dynamic, dynamic> envelope,
      List<dynamic> p,
      Map<String, Map<String, dynamic>> keys) async {
    if (p.length != 9 || p[0] != 1) {
      throw const EncryptionException('Encrypted message context is invalid.');
    }
    _checkContext(message, p, 4);
    final sender = _sender(keys, p[2]);
    var signed = false;
    // Only authenticated account versions (pin, forward and back-signed).
    for (final a in sender['accounts'] as List) {
      if (await _verify(
          _json(p), envelope['signature'], (a as Map)['signing_key'])) {
        signed = true;
        break;
      }
    }
    if (!signed) {
      throw const EncryptionException(
          'Encrypted message signature is invalid.');
    }
    final self = _selves[message.channelId]!;
    final mine = (p[8] as List)
        .cast<List<dynamic>>()
        .where((r) => r.length == 3 && r[0] == self)
        .toList();
    if (mine.length != 1) {
      throw const EncryptionException(
          'This message was not encrypted for you.');
    }
    final account =
        _keyring.where((a) => a.exchangeKey == mine.single[1]).firstOrNull;
    if (account == null) {
      throw const EncryptionException(
          'This message was encrypted for another identity.');
    }
    final context = _contextV1(p);
    // HKDF binds the RECIPIENT static key; DH uses the SENDER ephemeral key.
    final wrapping = await _derive(
        account.exchange,
        p[6] as String,
        _json([
          'daccord-e2ee-wrap-v1',
          base64Encode(context),
          self,
          account.exchangeKey
        ]));
    final key = SecretKey(await _open(mine.single[2] as String, wrapping,
        _json([base64Encode(context), self, account.exchangeKey])));
    return (jsonDecode(utf8.decode(await _open(p[7] as String, key, context)))
            as Map)
        .cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> _openV2(
      AccordMessage message,
      Map<dynamic, dynamic> envelope,
      List<dynamic> p,
      Map<String, Map<String, dynamic>> keys,
      {required bool refresh}) async {
    if (envelope.length != 2 ||
        !envelope.containsKey('signature') ||
        p.length != 11 ||
        p[0] != 2 ||
        p[3] is! String ||
        p[4] is! String ||
        p[7] is! String ||
        p[8] is! String ||
        p[9] is! List ||
        p[10] is! int ||
        (p[10] as int) < 1) {
      throw const EncryptionException('Encrypted message context is invalid.');
    }
    _checkContext(message, p, 5);
    var sender = _sender(keys, p[2]);
    if (!_knowsVersion(sender, p[10]) && refresh) {
      // The author rotated since we last looked: advance the pin (only along
      // a verified succession chain).
      sender = _sender(
          await participants(message.channelId, requireReady: false), p[2]);
    }
    if (!_knowsVersion(sender, p[10])) {
      throw const EncryptionException(
          'Sender encryption keys could not be verified.');
    }
    // The device was certified by a verified account version when pinned.
    final device = (sender['devices'] as Map?)?[p[3]] as Map?;
    if (device == null) {
      throw const EncryptionException(
          'Sender encryption device is unavailable.');
    }
    if ((p[10] as int) < (device['account_version'] as int)) {
      throw const EncryptionException(
          'Encrypted message account version is invalid.');
    }
    if (!await _verify(
        _json(p), envelope['signature'], device['signing_key'])) {
      throw const EncryptionException(
          'Encrypted message signature is invalid.');
    }
    final self = _selves[message.channelId]!;
    final own = _device!;
    final entries = (p[9] as List)
        .whereType<List<dynamic>>()
        .where((r) => r.length == 4 && r[0] == self)
        .toList();
    KeyPair? pair;
    List<dynamic>? mine;
    for (final r in entries) {
      if (r[1] == own.id && r[2] == own.exchangeKey) {
        pair = own.exchange;
        mine = r;
        break;
      }
    }
    if (mine == null) {
      for (final r in entries) {
        if (r[1] != 'account') continue;
        final account =
            _keyring.where((a) => a.exchangeKey == r[2]).firstOrNull;
        if (account != null) {
          pair = account.exchange;
          mine = r;
          break;
        }
      }
    }
    if (mine == null || pair == null) {
      throw const EncryptionException(
          'This message was not encrypted for this device.');
    }
    final context = _contextV2(p);
    final user = mine[0] as String;
    final keyId = mine[1] as String;
    final public = mine[2] as String;
    final wrapping = await _derive(
        pair, p[7] as String, _wrapInfo(context, user, keyId, public));
    final key = SecretKey(await _open(
        mine[3] as String, wrapping, _wrapAad(context, user, keyId, public)));
    return (jsonDecode(utf8.decode(await _open(p[8] as String, key, context)))
            as Map)
        .cast<String, dynamic>();
  }

  Future<Uint8List> downloadAttachment(AccordAttachment attachment,
      {required String cdnUrl}) async {
    final uri =
        Uri.parse(AccordCDN.resolvePath(attachment.url, cdnUrl: cdnUrl));
    final cdn =
        Uri.parse(attachment.encryption?['cdn_url'] as String? ?? cdnUrl);
    if (uri.origin != cdn.origin || !uri.path.startsWith('${cdn.path}/')) {
      throw const EncryptionException(
          'Encrypted attachment is outside the trusted server CDN.');
    }
    if (attachment.size < 0 || attachment.size > 100 * 1024 * 1024) {
      throw const EncryptionException('Attachment exceeds download limit.');
    }
    final result =
        await rest.downloadOpaque(uri, maxBytes: attachment.size + 28);
    if (!result.ok || result.data is! List<int>) {
      throw const EncryptionException(
          'Unable to download encrypted attachment.');
    }
    return decryptAttachment(attachment, result.data as List<int>);
  }

  Future<Uint8List> decryptAttachment(
      AccordAttachment attachment, List<int> bytes) async {
    final meta = attachment.encryption;
    if (meta == null) return Uint8List.fromList(bytes);
    final clear = await _open(
        base64Encode(bytes),
        SecretKey(base64Decode(meta['key'] as String)),
        _json(['daccord-e2ee-file-v1', meta['channel_id']]));
    if (clear.length != attachment.size) {
      throw const EncryptionException('Encrypted attachment size is invalid.');
    }
    return Uint8List.fromList(clear);
  }

  Future<String> fingerprint(Map<String, dynamic> identity) async {
    final hash = await Sha256()
        .hash(_json([identity['exchange_key'], identity['signing_key']]));
    final hex =
        hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return [for (var i = 0; i < hex.length; i += 8) hex.substring(i, i + 8)]
        .join(' ');
  }

  // ── Backups ───────────────────────────────────────────────────────────────

  static Future<SecretKey> _backupKey(String password, List<int> salt) =>
      Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 600000, bits: 256)
          .deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);

  /// Backup v2: the whole account keyring, sealed with [password].
  Future<String> exportBackup(String password) async {
    if (password.length < 12) {
      throw const EncryptionException(
          'Use a backup passphrase of at least 12 characters.');
    }
    await initialize();
    _requireActive();
    final salt = _random(16);
    return jsonEncode({
      'version': 2,
      'scope': _scope,
      'salt': base64Encode(salt),
      'box': await _seal(
          utf8.encode(_keyringJson(_keyring)),
          await _backupKey(password, salt),
          _json(['daccord-e2ee-backup-v1', _scope]))
    });
  }

  /// Imports a v1 (single identity) or v2 (keyring) backup; this device then
  /// certifies itself and becomes active. The backup must contain the
  /// account's current key, never older than keys this device already knew,
  /// and must not replace keyring versions this device already holds.
  Future<void> importBackup(String backup, String password) async {
    final data = jsonDecode(backup) as Map;
    if ((data['version'] != 1 && data['version'] != 2) ||
        data['scope'] != _scope) {
      throw const EncryptionException(
          'Backup belongs to another account or server.');
    }
    final salt = base64Decode(data['salt'] as String);
    if (salt.length != 16) {
      throw const EncryptionException('Invalid backup salt.');
    }
    final raw = utf8.decode(await _open(
        data['box'] as String,
        await _backupKey(password, salt),
        _json(['daccord-e2ee-backup-v1', _scope])));
    final List<_Account> imported;
    if (data['version'] == 1) {
      final secret = jsonDecode(raw) as Map;
      imported = [
        await _accountFrom(1, secret['exchange_private'] as String,
            secret['signing_private'] as String)
      ];
    } else {
      imported = await _parseKeyring(raw);
    }
    const stale = EncryptionException(
        'This backup does not contain your current encryption key. Approve this device from another device instead.');
    await _serialized(() async {
      if (_device == null) await _loadLocal();
      final state = await _fetchState();
      var account = _map(state['account']);
      if (account == null) {
        if (imported.length != 1 ||
            imported.single.version != 1 ||
            _floorVersion > 1) {
          throw const EncryptionException('Backup identity was rejected.');
        }
        final result =
            await rest.makeRequest('PUT', '/users/@me/encryption', body: {
          'exchange_key': imported.single.exchangeKey,
          'signing_key': imported.single.signingKey,
        });
        if (!result.ok) {
          throw EncryptionException(
              result.error?.message ?? 'Backup identity was rejected.');
        }
        account = imported.single.public;
      }
      final version = account['version'] as int? ?? 1;
      if (version < _floorVersion ||
          (_holdsKeyring && version < _keyring.last.version)) {
        throw const EncryptionException(blockedMessage);
      }
      final merged = {for (final a in imported) a.version: a};
      if (_holdsKeyring) {
        for (final a in _keyring) {
          final other = merged[a.version];
          if (other != null && !other.sameAs(a)) {
            throw const EncryptionException(
                'This backup belongs to different encryption keys.');
          }
          merged[a.version] = a;
        }
      }
      final keyring =
          (merged.keys.toList()..sort()).map((v) => merged[v]!).toList();
      if (keyring.last.version != version ||
          !_sameKeys(keyring.last.public, account)) {
        throw stale;
      }
      await _writeKeyring(keyring);
      await _setStaged(null);
      var result = await _putDevice(certifyWith: keyring.last);
      if (result.statusCode == 403) {
        await _writeDevice(await _newDevice());
        result = await _putDevice(certifyWith: keyring.last);
      }
      if (!result.ok) {
        throw EncryptionException(
            result.error?.message ?? 'Backup identity was rejected.');
      }
      await _setLinkKey(null);
      await _raiseFloor(version);
      _setSetup(PrivateChatSetup.active);
    });
    _initializing = Future<void>.value();
  }
}
