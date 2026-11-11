// In-memory Accord server for private chat encryption tests. Implements the
// v2 device endpoints, discovery and message admission from the shared
// e2ee-v2 spec closely enough to catch wire mismatches (recipient order,
// certificates, signatures, successions).
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:accordkit/accordkit.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MemoryKeys implements EncryptionKeyStore {
  final Map<String, String> values = {};
  bool failWrites = false;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('vault unavailable');
    values[key] = value;
  }
}

List<int> _json(Object? value) => utf8.encode(jsonEncode(value));

Future<bool> verifySignature(
  List<int> message,
  Object? signature,
  Object? publicKey,
) async {
  if (signature is! String || publicKey is! String) return false;
  try {
    final bytes = base64Decode(signature);
    if (bytes.length != 64) return false;
    return await Ed25519().verify(
      message,
      signature: Signature(
        bytes,
        publicKey: SimplePublicKey(
          base64Decode(publicKey),
          type: KeyPairType.ed25519,
        ),
      ),
    );
  } catch (_) {
    return false;
  }
}

class FakeAccount {
  final int version;
  String exchangeKey;
  String signingKey;
  String? signature;
  String? backSignature;
  FakeAccount(
    this.version,
    this.exchangeKey,
    this.signingKey, [
    this.signature,
    this.backSignature,
  ]);
  Map<String, dynamic> get identity => {
    'exchange_key': exchangeKey,
    'signing_key': signingKey,
  };
}

class FakeUser {
  final String id;
  final List<FakeAccount> accounts = [];
  final Map<String, Map<String, dynamic>> devices = {};
  final Map<String, String> packages = {};
  final Set<String> revoked = {};
  FakeUser(this.id);
  FakeAccount? get account => accounts.isEmpty ? null : accounts.last;
}

typedef ServerEvent = ({String user, String type, Map<String, dynamic> data});

class E2eeServer {
  final users = <String, FakeUser>{};
  final current = <String>['alice', 'bob'];

  /// session token → user id
  final sessions = <String, String>{};
  final deletedSessions = <String>{};
  final requests = <Map<String, dynamic>>[];
  final paths = <String>[];
  final events = <ServerEvent>[];
  final tokens = <String>{};
  final sealedFiles = <List<int>>[];
  final List<Map<String, dynamic>> history = [];
  String? wireContent;
  List<Map<String, dynamic>> wireAttachments = [];
  bool rejectDiscovery = false;

  /// Requests answered with 503 before the server starts working.
  int failures = 0;

  /// Runs once before admitting the next private message (to race a change).
  Future<void> Function()? beforeAdmit;

  /// Answer every private message write with 409.
  bool alwaysConflict = false;

  /// Omit the unsigned version-1 entry from `successions`, as servers did
  /// before it was added (clients must handle both shapes).
  bool legacySuccessions = false;

  /// A server without v2 (accordserver before per-device keys): no
  /// `GET /users/@me/encryption`, device or rotation endpoints (405), v1-only
  /// discovery rows, and v2 envelopes are refused.
  bool legacy = false;

  /// A v1 chat home: discovery rows carry no v2 fields.
  bool v1Discovery = false;

  /// Apply the next rotation, then answer 503 (a lost response).
  bool loseRotationResponse = false;
  int messageAttempts = 0;

  FakeUser user(String id) => users.putIfAbsent(id, () => FakeUser(id));

  static http.Response ok(Object? data) => http.Response(
    jsonEncode({'data': data}),
    200,
    headers: {'content-type': 'application/json'},
  );
  static http.Response error(int status, String message) => http.Response(
    jsonEncode({
      'error': {'code': 'error', 'message': message},
    }),
    status,
    headers: {'content-type': 'application/json'},
  );

  Map<String, dynamic> deviceRow(Map<String, dynamic> d, {String? token}) => {
    'device_id': d['device_id'],
    'name': d['name'],
    'exchange_key': d['exchange_key'],
    'signing_key': d['signing_key'],
    'certificate': d['certificate'],
    'account_version': d['account_version'],
    'status': d['status'],
    'created_at': d['created_at'],
    'last_seen_at': d['last_seen_at'],
    'current': token != null && d['session'] == token,
  };

  Future<bool> _certificateValid(
    FakeUser u,
    String deviceId,
    Map body,
    Object? certificate,
    int version,
  ) async {
    final account = u.accounts.where((a) => a.version == version).firstOrNull;
    if (account == null) return false;
    return verifySignature(
      _json([
        'daccord-e2ee-device-v2',
        u.id,
        version,
        deviceId,
        body['exchange_key'],
        body['signing_key'],
      ]),
      certificate,
      account.signingKey,
    );
  }

  Map<String, dynamic>? _boundDevice(FakeUser u, String token) => u
      .devices
      .values
      .where((d) => d['session'] == token && d['status'] == 'active')
      .firstOrNull;

  List<List<String>> expectedRecipients() {
    final out = <List<String>>[];
    for (final id in current) {
      final u = users[id];
      if (u?.account == null) {
        throw StateError('participant $id has no encryption identity');
      }
      out.add([id, 'account', u!.account!.exchangeKey]);
      for (final d in u.devices.values) {
        if (d['status'] == 'active') {
          out.add([id, d['device_id'] as String, d['exchange_key'] as String]);
        }
      }
    }
    out.sort((a, b) {
      final c = a[0].compareTo(b[0]);
      return c != 0 ? c : a[1].compareTo(b[1]);
    });
    return out;
  }

  /// Server admission of a private message (structure, sender device,
  /// signature, token replay and the exact recipient set).
  Future<http.Response?> admit(String author, String content) async {
    messageAttempts++;
    if (beforeAdmit != null) {
      final hook = beforeAdmit!;
      beforeAdmit = null;
      await hook();
    }
    if (alwaysConflict) {
      return error(409, 'Encryption keys changed. Refresh before sending.');
    }
    if (content.startsWith(PrivateChatEncryption.prefixV1)) {
      return _admitV1(author, content);
    }
    if (legacy) {
      return error(
        400,
        'Private chats require end-to-end encryption. Upgrade your client.',
      );
    }
    if (!content.startsWith(PrivateChatEncryption.prefixV2)) {
      return error(400, 'Private chats require end-to-end encryption.');
    }
    final envelope =
        jsonDecode(content.substring(PrivateChatEncryption.prefixV2.length))
            as Map;
    if (envelope.length != 2) return error(400, 'invalid E2EE envelope');
    final p = envelope['payload'] as List;
    final u = users[author]!;
    if (p.length != 11 || p[0] != 2 || p[1] != 'chat' || p[2] != author) {
      return error(400, 'E2EE message context does not match request');
    }
    // R5: the signed sender account version is the author's current one.
    if (p[10] is! int || (p[10] as int) < 1) {
      return error(400, 'invalid E2EE account version');
    }
    if (p[10] != u.account!.version) {
      return error(409, 'Encryption keys changed. Refresh before sending.');
    }
    final device = u.devices[p[3]];
    if (device == null || device['status'] != 'active') {
      return error(403, 'E2EE sender device is not active');
    }
    if (device['account_version'] != p[10]) {
      return error(409, 'Encryption keys changed. Refresh before sending.');
    }
    if (!await _certificateValid(
      u,
      p[3] as String,
      device,
      device['certificate'],
      u.account!.version,
    )) {
      return error(400, 'E2EE sender device is not active');
    }
    if (!await verifySignature(
      _json(p),
      envelope['signature'],
      device['signing_key'],
    )) {
      return error(400, 'E2EE signature verification failed');
    }
    final recipients = [
      for (final r in p[9] as List) [(r as List)[0], r[1], r[2]],
    ];
    if (jsonEncode(recipients) != jsonEncode(expectedRecipients())) {
      return error(409, 'Encryption keys changed. Refresh before sending.');
    }
    for (final r in p[9] as List) {
      if (base64Decode((r as List)[3] as String).length != 60) {
        return error(400, 'invalid wrapped key');
      }
    }
    if (!tokens.add('$author:${p[4]}')) {
      return error(409, 'Encrypted message was already accepted');
    }
    return null;
  }

  /// A malicious server showing session token → a different account key.
  final accountOverride = <String, FakeAccount>{};

  Map<String, dynamic> _state(FakeUser u, String token) => {
    'user_context': u.id,
    'account': accountOverride[token] != null
        ? {
            'version': accountOverride[token]!.version,
            ...accountOverride[token]!.identity,
          }
        : u.account == null
        ? null
        : {'version': u.account!.version, ...u.account!.identity},
    'successions': u.account == null ? [] : _successions(u),
    'devices': [
      for (final d in u.devices.values)
        if (d['status'] != 'revoked') deviceRow(d, token: token),
    ],
  };

  /// `key_package` is a JSON string `{"ephemeral", "box"}` of at most 16 KiB.
  static bool _validPackage(Object? package) {
    if (package is! String || utf8.encode(package).length > 16 * 1024) {
      return false;
    }
    try {
      final data = jsonDecode(package);
      return data is Map &&
          base64Decode(data['ephemeral'] as String).length == 32 &&
          base64Decode(data['box'] as String).length >= 28;
    } catch (_) {
      return false;
    }
  }

  List<Map<String, dynamic>> _successions(FakeUser u) => [
    for (final a in u.accounts.skip(legacySuccessions ? 1 : 0))
      {
        'version': a.version,
        'exchange_key': a.exchangeKey,
        'signing_key': a.signingKey,
        'signature': a.signature,
        'back_signature': a.backSignature,
      },
  ];

  /// v1 admission (also on v2 servers): one recipient per current
  /// participant, sorted, each with their CURRENT account exchange key, and a
  /// signature by the author's CURRENT account signing key.
  Future<http.Response?> _admitV1(String author, String content) async {
    final envelope =
        jsonDecode(content.substring(PrivateChatEncryption.prefixV1.length))
            as Map;
    final p = envelope['payload'] as List;
    if (envelope.length != 2 ||
        p.length != 9 ||
        p[0] != 1 ||
        p[1] != 'chat' ||
        p[2] != author) {
      return error(400, 'E2EE message context does not match request');
    }
    final recipients = p[8] as List;
    final expected = [...current]..sort();
    if (recipients.length != expected.length) {
      return error(400, 'E2EE recipients must match current chat membership');
    }
    for (var i = 0; i < expected.length; i++) {
      final r = recipients[i] as List;
      final key = users[expected[i]]?.account;
      if (r.length != 3 || r[0] != expected[i]) {
        return error(400, 'invalid or duplicate E2EE recipient');
      }
      if (key == null) {
        return error(400, 'Every participant must set up encryption.');
      }
      if (r[1] != key.exchangeKey) {
        return error(409, 'Encryption keys changed. Refresh before sending.');
      }
      if (base64Decode(r[2] as String).length != 60) {
        return error(400, 'invalid wrapped key');
      }
    }
    if (!await verifySignature(
      _json(p),
      envelope['signature'],
      users[author]!.account!.signingKey,
    )) {
      return error(400, 'E2EE signature verification failed');
    }
    if (!tokens.add('$author:${p[3]}')) {
      return error(409, 'Encrypted message was already accepted');
    }
    return null;
  }

  Map<String, dynamic> _discoveryRow(FakeUser u) => legacy || v1Discovery
      ? {
          'user_id': u.id,
          'wire_user_id': u.id,
          'current': current.contains(u.id),
          'identity': u.account!.identity,
        }
      : {
          'user_id': u.id,
          'wire_user_id': u.id,
          'current': current.contains(u.id),
          'identity': u.account!.identity,
          'account_version': u.account!.version,
          'successions': _successions(u),
          'devices': [
            for (final d in u.devices.values)
              if (d['status'] != 'pending')
                {
                  'device_id': d['device_id'],
                  'exchange_key': d['exchange_key'],
                  'signing_key': d['signing_key'],
                  'certificate': d['certificate'],
                  'account_version': d['account_version'],
                  'revoked': d['status'] == 'revoked',
                },
          ],
        };

  Map<String, dynamic>? _multipartPayload(http.Request request) {
    final text = utf8.decode(request.bodyBytes, allowMalformed: true);
    final start = text.indexOf('name="payload_json"');
    if (start < 0) return null;
    final body = text.indexOf('\r\n\r\n', start) + 4;
    final end = text.indexOf('\r\n--', body);
    return (jsonDecode(text.substring(body, end)) as Map)
        .cast<String, dynamic>();
  }

  Future<http.Response> handle(String token, http.Request request) async {
    if (failures > 0) {
      failures--;
      return http.Response('{}', 503);
    }
    if (deletedSessions.contains(token)) return error(401, 'Unauthorized');
    final uid = sessions[token]!;
    final path = request.url.path.replaceFirst('/api/v1', '');
    final method = request.method;
    paths.add('$method $path');
    final multipart =
        request.headers['content-type']?.startsWith('multipart/') == true;
    final body = multipart || request.bodyBytes.isEmpty
        ? null
        : jsonDecode(request.body);
    final u = user(uid);
    final now = DateTime.now().toUtc().toIso8601String();
    if (legacy &&
        path.startsWith('/users/@me/encryption') &&
        !(path == '/users/@me/encryption' && method == 'PUT')) {
      return http.Response('', 405);
    }
    if (path == '/users/@me/encryption') {
      if (method == 'GET') return ok(_state(u, token));
      final key = (body as Map).cast<String, dynamic>();
      if (u.account != null) {
        return jsonEncode(u.account!.identity) == jsonEncode(key)
            ? ok(key)
            : error(
                409,
                'This account already has an encryption identity. Import its encrypted backup on this device.',
              );
      }
      u.accounts.add(
        FakeAccount(
          1,
          key['exchange_key'] as String,
          key['signing_key'] as String,
        ),
      );
      return ok(key);
    }
    final device = RegExp(
      r'^/users/@me/encryption/devices/([^/]+)(/approve|/package)?$',
    ).firstMatch(path);
    if (device != null) {
      final id = device[1]!;
      final row = u.devices[id];
      switch ((method, device[2])) {
        case ('PUT', null):
          final b = (body as Map).cast<String, dynamic>();
          if (u.revoked.contains(id)) {
            return error(403, 'This device was removed from encrypted chats.');
          }
          if (row != null &&
              (row['exchange_key'] != b['exchange_key'] ||
                  row['signing_key'] != b['signing_key'])) {
            return error(409, 'Device keys are immutable.');
          }
          if (row == null &&
              u.devices.values.where((d) => d['status'] != 'revoked').length >=
                  20) {
            return error(400, 'Too many encryption devices.');
          }
          // R6: proof of the device key for this session's bearer token.
          final digest = base64Encode(
            (await Sha256().hash(utf8.encode(token))).bytes,
          );
          if (!await verifySignature(
            _json(['daccord-e2ee-bind-v2', uid, id, digest]),
            b['binding'],
            b['signing_key'],
          )) {
            return error(400, 'Invalid device binding.');
          }
          final next =
              row ??
              {
                'device_id': id,
                'exchange_key': b['exchange_key'],
                'signing_key': b['signing_key'],
                'certificate': null,
                'account_version': null,
                'status': 'pending',
                'created_at': now,
              };
          next['name'] = b['name'];
          if (b['certificate'] != null) {
            if (u.account == null) {
              return error(400, 'Register the account identity first.');
            }
            if (b['account_version'] != u.account!.version) {
              return error(409, 'Stale account version.');
            }
            if (!await _certificateValid(
              u,
              id,
              b,
              b['certificate'],
              u.account!.version,
            )) {
              return error(400, 'Invalid device certificate.');
            }
            if (next['status'] != 'active') {
              events.add((
                user: uid,
                type: 'encryption.devices_update',
                data: {},
              ));
            }
            next['certificate'] = b['certificate'];
            next['account_version'] = b['account_version'];
            next['status'] = 'active';
          }
          next['session'] = token;
          next['last_seen_at'] = now;
          final created = row == null;
          u.devices[id] = next;
          if (created && next['status'] == 'pending') {
            events.add((
              user: uid,
              type: 'encryption.device_pending',
              data: deviceRow(next),
            ));
          }
          return ok(deviceRow(next, token: token));
        case ('POST', '/approve'):
          final b = (body as Map).cast<String, dynamic>();
          if (_boundDevice(u, token) == null) {
            return error(403, 'Approve from an active device.');
          }
          if (row == null) return error(404, 'Unknown device.');
          if (row['status'] != 'pending') {
            return error(409, 'This device is not waiting for approval.');
          }
          if (!_validPackage(b['key_package'])) {
            return error(400, 'Invalid key package.');
          }
          if (b['account_version'] != u.account!.version ||
              !await _certificateValid(
                u,
                id,
                row,
                b['certificate'],
                u.account!.version,
              )) {
            return error(400, 'Invalid device certificate.');
          }
          row['certificate'] = b['certificate'];
          row['account_version'] = b['account_version'];
          row['status'] = 'active';
          u.packages[id] = b['key_package'] as String;
          events.add((user: uid, type: 'encryption.devices_update', data: {}));
          return ok(deviceRow(row, token: token));
        case ('GET', '/package'):
        case ('DELETE', '/package'):
          if (row == null || row['session'] != token) {
            return error(403, 'Not this device.');
          }
          final package = u.packages[id];
          if (package == null) return error(404, 'No key package.');
          if (method == 'DELETE') {
            u.packages.remove(id);
            return http.Response('', 204);
          }
          return ok({'key_package': package});
        case ('DELETE', null):
          if (row == null) return error(404, 'Unknown device.');
          if (row['status'] == 'active') {
            return error(409, 'Use rotation to remove an active device.');
          }
          if (_boundDevice(u, token) == null && row['session'] != token) {
            return error(403, 'Decline from an active device.');
          }
          u.devices.remove(id);
          events.add((user: uid, type: 'encryption.devices_update', data: {}));
          return http.Response('', 204);
      }
    }
    if (path == '/users/@me/encryption/rotate' && method == 'POST') {
      final b = (body as Map).cast<String, dynamic>();
      final caller = _boundDevice(u, token);
      final revoke = (b['revoke'] as List).cast<String>();
      if (caller == null || revoke.contains(caller['device_id'])) {
        return error(400, 'Rotate from an active device that stays.');
      }
      final account = (b['account'] as Map).cast<String, dynamic>();
      final version = b['version'];
      if (version != u.account!.version + 1) {
        return error(409, 'Stale account version.');
      }
      if (u.accounts.any(
            (a) =>
                a.exchangeKey == account['exchange_key'] ||
                a.signingKey == account['signing_key'],
          ) ||
          !await verifySignature(
            _json([
              'daccord-e2ee-rotate-v2',
              uid,
              version,
              account['exchange_key'],
              account['signing_key'],
            ]),
            b['signature'],
            u.account!.signingKey,
          ) ||
          !await verifySignature(
            _json([
              'daccord-e2ee-rotate-back-v2',
              uid,
              version,
              u.account!.exchangeKey,
              u.account!.signingKey,
            ]),
            b['back_signature'],
            account['signing_key'],
          )) {
        return error(400, 'Invalid succession.');
      }
      final remaining = {
        for (final d in u.devices.values)
          if (d['status'] == 'active' && !revoke.contains(d['device_id']))
            d['device_id'] as String,
      };
      final certificates = {
        for (final d in b['devices'] as List)
          (d as Map)['device_id'] as String: d['certificate'],
      };
      final packages = {
        for (final d in b['packages'] as List)
          (d as Map)['device_id'] as String: d['key_package'] as String,
      };
      if (revoke.any((id) => u.devices[id]?['status'] != 'active') ||
          !remaining.containsAll(certificates.keys) ||
          certificates.length != remaining.length ||
          packages.length != remaining.length - 1 ||
          packages.containsKey(caller['device_id']) ||
          !remaining.containsAll(packages.keys)) {
        return error(409, 'Rotation must cover exactly the remaining devices.');
      }
      if (!packages.values.every(_validPackage)) {
        return error(400, 'Invalid key package.');
      }
      final next = FakeAccount(
        version as int,
        account['exchange_key'] as String,
        account['signing_key'] as String,
        b['signature'] as String,
        b['back_signature'] as String,
      );
      u.accounts.add(next);
      for (final id in remaining) {
        if (!await _certificateValid(
          u,
          id,
          u.devices[id]!,
          certificates[id],
          version,
        )) {
          u.accounts.removeLast();
          return error(400, 'Invalid device certificate.');
        }
      }
      for (final id in remaining) {
        u.devices[id]!['certificate'] = certificates[id];
        u.devices[id]!['account_version'] = version;
      }
      for (final id in revoke) {
        final d = u.devices[id]!;
        d['status'] = 'revoked';
        u.revoked.add(id);
        u.packages.remove(id);
        if (d['session'] != null) deletedSessions.add(d['session'] as String);
      }
      u.devices.removeWhere((_, d) => d['status'] == 'pending');
      u.packages.addAll(packages);
      events.add((user: uid, type: 'encryption.devices_update', data: {}));
      if (loseRotationResponse) {
        loseRotationResponse = false;
        return http.Response('{}', 503); // Applied, but the reply was lost.
      }
      return ok(_state(u, token));
    }
    if (path == '/channels/chat/encryption') {
      if (rejectDiscovery) return http.Response('{}', 503);
      return ok({
        'channel_id': 'chat',
        'self_user_id': uid,
        'participants': [
          for (final u in users.values)
            if (u.account != null) _discoveryRow(u),
          for (final id in current.where((id) => users[id]?.account == null))
            {
              'user_id': id,
              'wire_user_id': id,
              'current': true,
              'identity': null,
            },
        ],
      });
    }
    if (path == '/channels/chat') return ok({'id': 'chat', 'type': 'group_dm'});
    if (path == '/channels/public') {
      return ok({'id': 'public', 'type': 'text', 'space_id': 'space'});
    }
    if (path.contains('/cdn/')) {
      return http.Response.bytes(sealedFiles.single, 200);
    }
    if (path.contains('/messages')) {
      final public = path.contains('public');
      if (method == 'GET') {
        if (path.endsWith('/messages')) return ok(history);
        return ok({
          'id': 'message',
          'channel_id': 'chat',
          'author_id': 'alice',
          'content': wireContent,
          'attachments': wireAttachments,
        });
      }
      final data = multipart ? _multipartPayload(request) : body as Map?;
      if (data != null) {
        final content = data['content'] as String;
        if (!public) {
          final refused = await admit(uid, content);
          if (refused != null) return refused;
        }
        requests.add(Map<String, dynamic>.from(data));
        wireContent = content;
        if (method == 'POST') {
          final files = multipart
              ? RegExp(
                  r'name="files\[',
                ).allMatches(latin1.decode(request.bodyBytes)).length
              : 0;
          wireAttachments = [
            for (var i = 0; i < files; i++)
              {
                'id': 'file$i',
                'filename': 'attachment-$i.bin',
                'url': '/cdn/attachments/file$i.bin',
                'size': 0,
              },
          ];
        }
        return ok({
          'id': 'message',
          'channel_id': public ? 'public' : 'chat',
          'author_id': uid,
          'content': wireContent,
          if (public) 'space_id': 'space',
        });
      }
    }
    throw StateError('Unexpected request: $method $path');
  }

  http.Client httpClient(String token) =>
      MockClient((request) => handle(token, request));
}

class Harness {
  final server = E2eeServer();
  final stores = <String, MemoryKeys>{};
  final clients = <String, AccordClient>{};
  List<String> get current => server.current;
  List<Map<String, dynamic>> get requests => server.requests;
  String? get wireContent => server.wireContent;
  List<List<int>> get sealedFiles => server.sealedFiles;
  set rejectDiscovery(bool value) => server.rejectDiscovery = value;

  /// A client for session [name] of [user] (default: [name]). Each session
  /// has its own vault, i.e. is a separate device.
  AccordClient client(String name, {String? user, MemoryKeys? store}) =>
      clients.putIfAbsent(name, () {
        server.sessions[name] = user ?? name;
        return AccordClient(
          token: name,
          tokenType: 'Bearer',
          baseUrl: 'https://chat.test',
          cdnUrl: 'https://chat.test/cdn',
          encryptionStore: store ?? stores.putIfAbsent(name, MemoryKeys.new),
          encryptionUserId: user ?? name,
          encryptionDeviceName: 'Device $name',
          httpClient: server.httpClient(name),
        );
      });

  PrivateChatEncryption e(String name) => client(name).encryption!;

  Future<void> setup() async {
    await e('alice').initialize();
    await e('bob').initialize();
  }

  /// Approves [pending] (a session of the same user) from [approver].
  Future<void> approve(String approver, String pending) async {
    final code = await e(pending).linkCode();
    final device = (await e(approver).listDevices()).firstWhere(
      (d) => d.status == EncryptionDeviceStatus.pending,
    );
    expect(await e(approver).linkCodeFor(device), code);
    await e(approver).approveDevice(device.deviceId);
    // R1: the new device waits for its user to confirm the codes matched.
    expect(await e(pending).checkApproval(), false);
    expect(e(pending).setup, PrivateChatSetup.approved);
    await e(pending).confirmApproval();
    expect(e(pending).setup, PrivateChatSetup.active);
    expect(await e(pending).checkApproval(), true);
  }

  /// Simulates an app restart of session [name]: same vault, new client.
  Future<PrivateChatEncryption> restart(String name, {String? user}) async {
    await clients.remove(name)?.dispose();
    final restarted = client(name, user: user).encryption!;
    await restarted.initialize();
    return restarted;
  }

  AccordMessage wire(
    String content, {
    String author = 'alice',
    String channel = 'chat',
    String? reply,
    List<AccordAttachment>? attachments,
  }) => AccordMessage(
    id: 'message',
    channelId: channel,
    authorId: author,
    content: content,
    replyTo: reply,
    attachments: attachments,
  );

  Future<void> close() async {
    for (final c in clients.values) {
      await c.dispose();
    }
  }
}

/// The v2 envelope payload of a sent message.
List<dynamic> payloadOf(String content) =>
    (jsonDecode(content.substring(content.indexOf('{'))) as Map)['payload']
        as List;

List<int> _random(int length) {
  final rng = Random.secure();
  return List.generate(length, (_) => rng.nextInt(256));
}

Future<String> _seal(List<int> bytes, SecretKey key, List<int> aad) async {
  final box = await AesGcm.with256bits().encrypt(
    bytes,
    secretKey: key,
    nonce: _random(12),
    aad: aad,
  );
  return base64Encode([...box.nonce, ...box.cipherText, ...box.mac.bytes]);
}

/// A v1 message as a pre-v2 client sent it (signed by the account key and
/// wrapped for each participant's account exchange key).
Future<String> encryptV1({
  required String author,
  required Map<String, String> authorSecret,
  required Map<String, String> recipients,
  required String content,
}) async {
  final signing = await Ed25519().newKeyPairFromSeed(
    base64Decode(authorSecret['signing_private']!),
  );
  final ephemeral = await X25519().newKeyPair();
  final p = <dynamic>[
    1,
    'chat',
    author,
    base64Encode(_random(16)),
    null,
    null,
    base64Encode((await ephemeral.extractPublicKey()).bytes),
    '',
    <dynamic>[],
  ];
  final context = _json(['daccord-e2ee-v1', ...p.sublist(1, 7)]);
  final key = SecretKey(_random(32));
  p[7] = await _seal(
    _json({'content': content, 'files': [], 'embeds': []}),
    key,
    context,
  );
  for (final id in recipients.keys.toList()..sort()) {
    final public = recipients[id]!;
    final shared = await X25519().sharedSecretKey(
      keyPair: ephemeral,
      remotePublicKey: SimplePublicKey(
        base64Decode(public),
        type: KeyPairType.x25519,
      ),
    );
    final wrapping = await Hkdf(hmac: Hmac.sha256(), outputLength: 32)
        .deriveKey(
          secretKey: shared,
          nonce: const [],
          info: _json([
            'daccord-e2ee-wrap-v1',
            base64Encode(context),
            id,
            public,
          ]),
        );
    (p[8] as List).add([
      id,
      public,
      await _seal(
        await key.extractBytes(),
        wrapping,
        _json([base64Encode(context), id, public]),
      ),
    ]);
  }
  final signature = await Ed25519().sign(_json(p), keyPair: signing);
  return '${PrivateChatEncryption.prefixV1}${jsonEncode({'payload': p, 'signature': base64Encode(signature.bytes)})}';
}

/// A key package sealed to a device per the spec (used to forge packages).
Future<String> sealPackage({
  required String user,
  required String deviceId,
  required String deviceExchangeKey,
  required String keyringJson,
}) async {
  final eph = await X25519().newKeyPair();
  final public = base64Encode((await eph.extractPublicKey()).bytes);
  final info = _json([
    'daccord-e2ee-package-v2',
    user,
    deviceId,
    deviceExchangeKey,
    public,
  ]);
  final shared = await X25519().sharedSecretKey(
    keyPair: eph,
    remotePublicKey: SimplePublicKey(
      base64Decode(deviceExchangeKey),
      type: KeyPairType.x25519,
    ),
  );
  final key = await Hkdf(
    hmac: Hmac.sha256(),
    outputLength: 32,
  ).deriveKey(secretKey: shared, nonce: const [], info: info);
  return jsonEncode({
    'ephemeral': public,
    'box': await _seal(utf8.encode(keyringJson), key, info),
  });
}

/// A v1 identity backup as the pre-v2 client exported it.
Future<String> v1Backup(
  String scope,
  String identityJson,
  String password,
) async {
  final salt = _random(16);
  final key = await Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 600000,
    bits: 256,
  ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
  return jsonEncode({
    'version': 1,
    'scope': scope,
    'salt': base64Encode(salt),
    'box': await _seal(
      utf8.encode(identityJson),
      key,
      _json(['daccord-e2ee-backup-v1', scope]),
    ),
  });
}

String scopeOf(String user) =>
    base64Url.encode(utf8.encode('https://chat.test/api/v1|$user'));

Uint8List bytesOf(String text) => Uint8List.fromList(utf8.encode(text));

/// Keys an attacker controls: each private key is 32 copies of a seed byte.
class SeededAccount {
  final int version;
  final int exchangeSeed;
  final int signingSeed;
  late final String exchangeKey;
  late final String signingKey;
  SeededAccount(this.version, this.exchangeSeed, this.signingSeed);

  Future<SeededAccount> init() async {
    exchangeKey = base64Encode(
      (await (await X25519().newKeyPairFromSeed(
        List.filled(32, exchangeSeed),
      )).extractPublicKey()).bytes,
    );
    signingKey = base64Encode(
      (await (await Ed25519().newKeyPairFromSeed(
        List.filled(32, signingSeed),
      )).extractPublicKey()).bytes,
    );
    return this;
  }

  Map<String, String> get secret => {
    'exchange_private': base64Encode(List.filled(32, exchangeSeed)),
    'signing_private': base64Encode(List.filled(32, signingSeed)),
  };
  String get keyringJson => jsonEncode({
    'accounts': [
      {'version': version, ...secret},
    ],
  });
  FakeAccount get fake => FakeAccount(version, exchangeKey, signingKey);

  Future<String> sign(List<Object?> message) async => base64Encode(
    (await Ed25519().sign(
      _json(message),
      keyPair: await Ed25519().newKeyPairFromSeed(List.filled(32, signingSeed)),
    )).bytes,
  );
}

/// The private device record of session [name] (as stored in its vault).
Map<String, dynamic> deviceSecret(Harness h, String name, {String? user}) =>
    jsonDecode(
          h.stores[name]!.values['e2ee.v2.${scopeOf(user ?? name)}.device']!,
        )
        as Map<String, dynamic>;

/// What a pre-v2 client does with a v1 envelope: verify the author's account
/// signature, unwrap its own entry with its account exchange key, decrypt.
Future<String> decryptAsOldClient({
  required String content,
  required String user,
  required SeededAccount account,
  required String authorSigningKey,
}) async {
  expect(content, startsWith(PrivateChatEncryption.prefixV1));
  final envelope =
      jsonDecode(content.substring(PrivateChatEncryption.prefixV1.length))
          as Map;
  final p = envelope['payload'] as List;
  expect(
    await verifySignature(_json(p), envelope['signature'], authorSigningKey),
    true,
  );
  final mine = (p[8] as List).cast<List<dynamic>>().singleWhere(
    (r) => r[0] == user,
  );
  expect(mine[1], account.exchangeKey);
  final context = _json(['daccord-e2ee-v1', ...p.sublist(1, 7)]);
  final shared = await X25519().sharedSecretKey(
    keyPair: await X25519().newKeyPairFromSeed(
      List.filled(32, account.exchangeSeed),
    ),
    remotePublicKey: SimplePublicKey(
      base64Decode(p[6] as String),
      type: KeyPairType.x25519,
    ),
  );
  final wrapping = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
    secretKey: shared,
    nonce: const [],
    info: _json([
      'daccord-e2ee-wrap-v1',
      base64Encode(context),
      user,
      account.exchangeKey,
    ]),
  );
  Future<List<int>> open(String encoded, SecretKey key, List<int> aad) {
    final bytes = base64Decode(encoded);
    return AesGcm.with256bits().decrypt(
      SecretBox(
        bytes.sublist(12, bytes.length - 16),
        nonce: bytes.sublist(0, 12),
        mac: Mac(bytes.sublist(bytes.length - 16)),
      ),
      secretKey: key,
      aad: aad,
    );
  }

  final key = SecretKey(
    await open(
      mine[2] as String,
      wrapping,
      _json([base64Encode(context), user, account.exchangeKey]),
    ),
  );
  final body = jsonDecode(
    utf8.decode(await open(p[7] as String, key, context)),
  );
  return (body as Map)['content'] as String;
}
