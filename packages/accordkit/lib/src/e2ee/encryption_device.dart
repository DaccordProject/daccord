/// Lifecycle of a per-device encryption key (private chat encryption v2).
enum EncryptionDeviceStatus { pending, active, revoked }

/// Whether this device can read and send private chats.
///
/// [unknown] until [PrivateChatEncryption.initialize] completes (or after it
/// failed); [pending] while another device still has to approve this one.
enum PrivateChatSetup { unknown, active, pending }

/// A device registered for the signed-in account's private chats.
class EncryptionDevice {
  final String deviceId;

  /// User-visible plaintext label chosen by the device (1–64 characters).
  final String name;
  final EncryptionDeviceStatus status;
  final DateTime? createdAt;
  final DateTime? lastSeenAt;

  /// True for the device this client runs on.
  final bool current;
  final String exchangeKey;
  final String signingKey;

  const EncryptionDevice({
    required this.deviceId,
    required this.name,
    required this.status,
    this.createdAt,
    this.lastSeenAt,
    this.current = false,
    required this.exchangeKey,
    required this.signingKey,
  });

  /// Parses a server `DeviceRow`. [currentDeviceId] marks this client's own
  /// device even when the row is bound to another of the user's sessions.
  factory EncryptionDevice.fromJson(Map<String, dynamic> json,
      {String? currentDeviceId}) {
    final id = json['device_id'] as String;
    return EncryptionDevice(
      deviceId: id,
      name: json['name'] as String? ?? '',
      status: switch (json['status']) {
        'active' => EncryptionDeviceStatus.active,
        'revoked' => EncryptionDeviceStatus.revoked,
        _ => EncryptionDeviceStatus.pending,
      },
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      lastSeenAt: DateTime.tryParse(json['last_seen_at'] as String? ?? ''),
      current: json['current'] == true || id == currentDeviceId,
      exchangeKey: json['exchange_key'] as String,
      signingKey: json['signing_key'] as String,
    );
  }

  @override
  String toString() =>
      'EncryptionDevice($deviceId, $name, ${status.name}${current ? ', current' : ''})';
}
