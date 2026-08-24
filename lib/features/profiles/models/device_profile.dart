/// A local device profile: an isolated namespace with its own `accord-session`
/// and `accord-settings` storage, with an optional casual UI PIN lock. The PIN
/// does not encrypt either store. Distinct from the
/// multi-account switcher (several server logins within one profile). Mirrors
/// the reference client's `config_profiles.gd` profile registry entries.
class DeviceProfile {
  const DeviceProfile({
    required this.id,
    required this.name,
    this.pinSalt = '',
    this.pinHash = '',
  });

  /// The default profile's fixed id. Its storage lives at the root data dir
  /// (so pre-profiles data is preserved) and it can never be deleted.
  static const String defaultId = 'default';

  /// Stable identifier / storage folder name (slug). `defaultId` for the
  /// default profile.
  final String id;

  /// User-facing display name.
  final String name;

  /// Hex salt for the PIN hash (empty when no PIN is set).
  final String pinSalt;

  /// Hex PIN hash (empty when no PIN is set).
  final String pinHash;

  bool get hasPin => pinHash.isNotEmpty;
  bool get isDefault => id == defaultId;

  DeviceProfile copyWith({String? name, String? pinSalt, String? pinHash}) =>
      DeviceProfile(
        id: id,
        name: name ?? this.name,
        pinSalt: pinSalt ?? this.pinSalt,
        pinHash: pinHash ?? this.pinHash,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'pinSalt': pinSalt,
    'pinHash': pinHash,
  };

  static DeviceProfile fromJson(Map<dynamic, dynamic> json) => DeviceProfile(
    id: (json['id'] ?? '').toString(),
    name: (json['name'] ?? '').toString(),
    pinSalt: (json['pinSalt'] ?? '').toString(),
    pinHash: (json['pinHash'] ?? '').toString(),
  );
}
