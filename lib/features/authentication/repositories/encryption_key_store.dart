import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/repositories/session_credential_vault.dart';
import 'package:flutter/foundation.dart';

/// Shares serialization with session vault writes on Linux Secret Service.
class PlatformEncryptionKeyStore implements EncryptionKeyStore {
  final SessionCredentialVault _vault = PlatformSessionCredentialVault();
  @override
  Future<String?> read(String key) => _vault.read(key);
  @override
  Future<void> write(String key, String value) => _vault.write(key, value);
}

/// The label other devices see when this one asks to join encrypted chats.
String encryptionDeviceName() {
  if (kIsWeb) return 'Daccord on Web';
  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS => 'Daccord on iOS',
    TargetPlatform.android => 'Daccord on Android',
    TargetPlatform.windows => 'Daccord on Windows',
    TargetPlatform.macOS => 'Daccord on macOS',
    TargetPlatform.linux => 'Daccord on Linux',
    TargetPlatform.fuchsia => 'Daccord on Fuchsia',
  };
}
