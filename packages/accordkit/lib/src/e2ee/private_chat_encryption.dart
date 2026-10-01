import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import '../models/attachment.dart';
import '../utils/cdn.dart';
import '../models/message.dart';
import '../rest/accord_rest.dart';

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

/// V1 account identity, per-message content keys, signed recipient envelopes.
/// No server secret, shared group key, plaintext fallback, or forward-secrecy claim.
class PrivateChatEncryption {
  static const prefix = 'daccord-e2ee:1:';
  final AccordRest rest;
  final EncryptionKeyStore store;
  final String userId;
  final X25519 _exchange = X25519();
  final Ed25519 _signing = Ed25519();
  final AesGcm _cipher = AesGcm.with256bits();
  final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  late SimpleKeyPair _exchangePair;
  late SimpleKeyPair _signingPair;
  late Map<String, dynamic> _identity;
  Future<void>? _initializing;
  final Map<String, Map<String, dynamic>> _trusted = {};
  final Map<String, String> _channels = {};
  final Map<String, String> _selves = {};
  final Map<String, String> _cdns = {};
  final Map<String, Map<String, String>> _aliases = {};
  static final Map<String, Future<void>> _storageQueues = {};
  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = (_storageQueues[_scope] ?? Future<void>.value())
        .then((_) => operation());
    _storageQueues[_scope] = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  PrivateChatEncryption(this.rest, this.store, this.userId);
  String get _scope => base64Url.encode(utf8.encode('${rest.baseUrl}|$userId'));
  bool knowsPrivateChat(String channelId) => _channels.containsKey(channelId);
  String get _identityKey => 'e2ee.v1.$_scope.identity';
  String get _trustKey => 'e2ee.v1.$_scope.trust';

  Future<void> initialize() =>
      _initializing ??= _serialized(_initialize).catchError((Object e) {
        _initializing = null;
        throw e;
      });

  Future<void> _initialize() async {
    var raw = await store.read(_identityKey);
    if (raw == null) {
      final x = await _exchange.newKeyPair();
      final s = await _signing.newKeyPair();
      raw = jsonEncode({
        'exchange_private': base64Encode(await x.extractPrivateKeyBytes()),
        'signing_private': base64Encode(await s.extractPrivateKeyBytes()),
      });
      // Persist before publishing: a failed vault write must never register a key.
      await store.write(_identityKey, raw);
    }
    await _loadIdentity(raw);
    final result =
        await rest.makeRequest('PUT', '/users/@me/encryption', body: _identity);
    if (!result.ok) {
      throw EncryptionException(
          result.error?.message ?? 'Unable to set up private chat encryption.');
    }
    final trust = await store.read(_trustKey);
    if (trust != null) {
      final entries = (jsonDecode(trust) as Map).cast<String, dynamic>();
      for (final entry in entries.entries) {
        _trusted[entry.key] = (entry.value as Map).cast<String, dynamic>();
      }
    }
  }

  Future<void> _loadIdentity(String raw) async {
    final secret = jsonDecode(raw) as Map;
    _exchangePair = await _exchange
        .newKeyPairFromSeed(base64Decode(secret['exchange_private'] as String));
    _signingPair = await _signing
        .newKeyPairFromSeed(base64Decode(secret['signing_private'] as String));
    _identity = {
      'exchange_key':
          base64Encode((await _exchangePair.extractPublicKey()).bytes),
      'signing_key':
          base64Encode((await _signingPair.extractPublicKey()).bytes),
    };
  }

  Future<Map<String, Map<String, dynamic>>> participants(String channelId,
      {bool requireReady = true}) async {
    await initialize();
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
    if (discovery['cdn_url'] is String)
      _cdns[channelId] = discovery['cdn_url'] as String;
    final rows = discovery['participants'] as List;
    final aliases = <String, String>{};
    final keys = <String, Map<String, dynamic>>{};
    for (final raw in rows) {
      final row = raw as Map;
      final identity = row['identity'];
      if (identity == null) {
        if (requireReady && row['current'] != false) {
          throw const EncryptionException(
              'Every participant must open an updated Daccord client to set up encryption.');
        }
        continue;
      }
      aliases[row['user_id'] as String] = row['wire_user_id'] as String;
      keys[row['wire_user_id'] as String] =
          (identity as Map).cast<String, dynamic>();
    }
    _aliases[channelId] = aliases;
    final self = _selves[channelId]!;
    if (keys[self]?['exchange_key'] != _identity['exchange_key'] ||
        keys[self]?['signing_key'] != _identity['signing_key']) {
      throw const EncryptionException(
          'Your encryption identity does not match this device. Import its encrypted backup.');
    }
    // Serialize with the vault's other updates and persist TOFU before use.
    final trust = _serialized(() async {
      final persisted = await store.read(_trustKey);
      if (persisted != null) {
        for (final e in (jsonDecode(persisted) as Map).entries) {
          _trusted[e.key as String] = (e.value as Map).cast<String, dynamic>();
        }
      }
      for (final e in keys.entries) {
        final previous = _trusted[e.key];
        if (previous != null &&
            (previous['exchange_key'] != e.value['exchange_key'] ||
                previous['signing_key'] != e.value['signing_key'])) {
          throw EncryptionException(
              'Encryption identity changed for ${e.key}. Sending and decryption are blocked.');
        }
      }
      await store.write(_trustKey, jsonEncode({..._trusted, ...keys}));
      _trusted.addAll(keys);
    });
    await trust;
    if (requireReady) {
      final current = <String>{
        for (final row in rows)
          if ((row as Map)['current'] != false) row['wire_user_id'] as String
      };
      keys.removeWhere((id, _) => !current.contains(id));
    }
    return keys;
  }

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
  List<int> _context(List<dynamic> p) =>
      _json(['daccord-e2ee-v1', ...p.sublist(1, 7)]);
  Future<String> _seal(List<int> bytes, SecretKey key, List<int> aad) async {
    final box = await _cipher.encrypt(bytes,
        secretKey: key, nonce: _random(12), aad: aad);
    return base64Encode([...box.nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  Future<List<int>> _open(String encoded, SecretKey key, List<int> aad) async {
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

  Future<SecretKey> _wrapKey(SimpleKeyPair pair, String publicKey,
      List<int> context, String recipient) async {
    final shared = await _exchange.sharedSecretKey(
        keyPair: pair,
        remotePublicKey:
            SimplePublicKey(base64Decode(publicKey), type: KeyPairType.x25519));
    if ((await shared.extractBytes()).every((v) => v == 0)) {
      throw const EncryptionException('Invalid recipient exchange key.');
    }
    return _hkdf.deriveKey(
        secretKey: shared,
        nonce: const [],
        info: _json([
          'daccord-e2ee-wrap-v1',
          base64Encode(context),
          recipient,
          publicKey
        ]));
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
    final keys =
        await participants(channelId); // Fresh membership on EVERY send/edit.
    final wireChannel = _channels[channelId]!;
    final wireSender = _selves[channelId]!;
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
    final p = <dynamic>[
      1,
      wireChannel,
      wireSender,
      base64Encode(_random(16)),
      _messageId(channelId, data['reply_to'] as String?),
      _messageId(channelId, editId),
      '',
      '',
      <dynamic>[]
    ];
    final ephemeral = await _exchange.newKeyPair();
    p[6] = base64Encode((await ephemeral.extractPublicKey()).bytes);
    final context = _context(p);
    final contentKey = SecretKey(_random(32));
    p[7] = await _seal(_json(privatePayload), contentKey, context);
    final ids = keys.keys.toList()..sort();
    for (final id in ids) {
      final publicKey = keys[id]!['exchange_key'] as String;
      final wrapping = await _wrapKey(ephemeral, publicKey, context, id);
      (p[8] as List).add([
        id,
        publicKey,
        await _seal(await contentKey.extractBytes(), wrapping,
            _json([base64Encode(context), id, publicKey]))
      ]);
    }
    final signature = await _signing.sign(_json(p), keyPair: _signingPair);
    return (
      data: {
        'content': '$prefix${jsonEncode({
              'payload': p,
              'signature': base64Encode(signature.bytes)
            })}',
        if (data['reply_to'] != null) 'reply_to': data['reply_to']
      },
      files: sealedFiles
    );
  }

  Future<AccordMessage> decrypt(AccordMessage message,
      {Map<String, Map<String, dynamic>>? participantKeys,
      Object? discoveryError}) async {
    if (!message.content.startsWith(prefix)) return message;
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
      final envelope = jsonDecode(encoded.substring(prefix.length)) as Map;
      final p = envelope['payload'] as List;
      final keys = participantKeys ??
          await participants(message.channelId, requireReady: false);
      final self = _selves[message.channelId]!;
      if (p.length != 9 ||
          p[0] != 1 ||
          p[1] != _channels[message.channelId] ||
          p[2] !=
              (_aliases[message.channelId]?[message.authorId] ??
                  message.authorId) ||
          p[4] != _messageId(message.channelId, message.replyTo) ||
          (p[5] != null && p[5] != _messageId(message.channelId, message.id))) {
        throw const EncryptionException(
            'Encrypted message context is invalid.');
      }
      // Removed authors' pinned identities remain usable for old history.
      final sender = keys[p[2]] ?? _trusted[p[2]];
      if (sender == null) {
        throw const EncryptionException(
            'Sender encryption identity is unavailable.');
      }
      if (!await _signing.verify(_json(p),
          signature: Signature(base64Decode(envelope['signature'] as String),
              publicKey: SimplePublicKey(
                  base64Decode(sender['signing_key'] as String),
                  type: KeyPairType.ed25519)))) {
        throw const EncryptionException(
            'Encrypted message signature is invalid.');
      }
      final recipients = p[8] as List;
      final mine =
          recipients.cast<List<dynamic>>().where((r) => r[0] == self).single;
      if (mine[1] != _identity['exchange_key']) {
        throw const EncryptionException(
            'This message was encrypted for another identity.');
      }
      final context = _context(p);
      // HKDF binds the RECIPIENT static key; DH uses the SENDER ephemeral key.
      final shared = await _exchange.sharedSecretKey(
          keyPair: _exchangePair,
          remotePublicKey: SimplePublicKey(base64Decode(p[6] as String),
              type: KeyPairType.x25519));
      if ((await shared.extractBytes()).every((v) => v == 0)) {
        throw const EncryptionException('Invalid sender exchange key.');
      }
      final wrapping = await _hkdf.deriveKey(
          secretKey: shared,
          nonce: const [],
          info: _json(
              ['daccord-e2ee-wrap-v1', base64Encode(context), self, mine[1]]));
      final key = SecretKey(await _open(mine[2] as String, wrapping,
          _json([base64Encode(context), self, mine[1]])));
      final payload =
          (jsonDecode(utf8.decode(await _open(p[7] as String, key, context)))
                  as Map)
              .cast<String, dynamic>();
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

  Future<SecretKey> _backupKey(String password, List<int> salt) =>
      Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 600000, bits: 256)
          .deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
  Future<String> exportBackup(String password) async {
    if (password.length < 12) {
      throw const EncryptionException(
          'Use a backup passphrase of at least 12 characters.');
    }
    await initialize();
    final salt = _random(16);
    final secret = await store.read(_identityKey);
    return jsonEncode({
      'version': 1,
      'scope': _scope,
      'salt': base64Encode(salt),
      'box': await _seal(utf8.encode(secret!), await _backupKey(password, salt),
          _json(['daccord-e2ee-backup-v1', _scope]))
    });
  }

  Future<void> importBackup(String backup, String password) async {
    final data = jsonDecode(backup) as Map;
    if (data['version'] != 1 || data['scope'] != _scope) {
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
    final previous = await store.read(_identityKey);
    try {
      await _loadIdentity(raw);
      final result = await rest.makeRequest('PUT', '/users/@me/encryption',
          body: _identity);
      if (!result.ok)
        throw EncryptionException(
            result.error?.message ?? 'Backup identity was rejected.');
      await store.write(_identityKey, raw);
    } catch (_) {
      if (previous != null) await _loadIdentity(previous);
      _initializing = null;
      rethrow;
    }
    _initializing = null;
    await initialize();
  }
}
