import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:bonfire/features/authentication/repositories/session_credential_vault.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'device_fingerprint.g.dart';

/// Reads the platform's stable device identifier, or null where there isn't a
/// usable one.
typedef DeviceIdSource = Future<String?> Function();

/// The abuse-prevention device fingerprint sent at registration, sign-in and
/// on every gateway READY, which lets instance admins ban a device rather than
/// only an account.
///
/// The raw identifier never leaves the device: each server receives
/// `sha256("daccord-device-v1\n" + rawId + "\n" + origin)`, so fingerprints
/// can't be linked across servers. The raw id is the OS device id (Android
/// `ANDROID_ID`, Windows device id, Linux machine id, macOS system GUID), or —
/// on iOS, the web, and whenever that's unavailable — a random 128-bit id
/// generated once and kept in the platform credential vault (the iOS Keychain
/// survives a reinstall; the web copy is cleared with site data).
///
/// Every failure resolves to null; callers omit the field rather than failing.
class DeviceFingerprint {
  DeviceFingerprint({
    DeviceIdSource? platformId,
    PlatformSessionCredentialVault? vault,
    Random? random,
  }) : _platformId = platformId ?? _readPlatformId,
       _vault = vault ?? PlatformSessionCredentialVault(),
       _random = random ?? Random.secure();

  /// Vault key of the generated fallback id.
  static const storageKey = 'daccord.device.v1';
  static const _channel = MethodChannel('com.daccord.app/device_id');

  final DeviceIdSource _platformId;
  final PlatformSessionCredentialVault _vault;
  final Random _random;

  String? _rawId;
  Future<String?>? _resolving;

  /// The raw device id, resolved once and then cached in memory. A failed
  /// resolution isn't cached, so a later call can still succeed.
  Future<String?> rawId() async {
    final cached = _rawId;
    if (cached != null) return cached;
    return _resolving ??= _resolve().then((id) {
      _resolving = null;
      return _rawId = id;
    });
  }

  /// This device's fingerprint for the server at [baseUrl], or null when it
  /// can't be computed.
  Future<String?> forServer(String baseUrl) async {
    try {
      final raw = await rawId();
      return raw == null ? null : derive(raw, baseUrl);
    } catch (error) {
      debugPrint('Device fingerprint unavailable: $error');
      return null;
    }
  }

  /// The per-server fingerprint of [rawId]: lowercase hex SHA-256 over the
  /// server's canonical endpoint identity.
  static String derive(String rawId, String baseUrl) {
    final origin = AccordServer.endpointIdentity(baseUrl);
    final input = 'daccord-device-v1\n$rawId\n$origin';
    return sha256.convert(utf8.encode(input)).toString();
  }

  Future<String?> _resolve() async {
    try {
      final id = (await _platformId())?.trim();
      if (id != null && id.isNotEmpty) return id;
    } catch (error) {
      debugPrint('Platform device id unavailable: $error');
    }
    return _storedId();
  }

  /// The generated fallback id, created and persisted on first use. Returns
  /// null when it can't be persisted: an id that changes every launch would
  /// only fill the server's device list with noise.
  Future<String?> _storedId() async {
    try {
      final existing = await _vault.readKey(storageKey);
      if (existing != null && existing.isNotEmpty) return existing;
      final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
      final id = [
        for (final b in bytes) b.toRadixString(16).padLeft(2, '0'),
      ].join();
      await _vault.writeKey(storageKey, id);
      return id;
    } catch (error) {
      debugPrint('Device id storage unavailable: $error');
      return null;
    }
  }

  static Future<String?> _readPlatformId() async {
    if (kIsWeb) return null;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _channel.invokeMethod<String>('androidId');
      case TargetPlatform.windows:
        return (await DeviceInfoPlugin().windowsInfo).deviceId;
      case TargetPlatform.linux:
        return (await DeviceInfoPlugin().linuxInfo).machineId;
      case TargetPlatform.macOS:
        return (await DeviceInfoPlugin().macOsInfo).systemGUID;
      // iOS's identifierForVendor resets when the app is reinstalled; the
      // Keychain-stored id doesn't.
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return null;
    }
  }
}

/// The app-wide [DeviceFingerprint]. Tests override it so no platform channel
/// or vault is touched.
@Riverpod(keepAlive: true)
DeviceFingerprint deviceFingerprint(Ref ref) => DeviceFingerprint();
