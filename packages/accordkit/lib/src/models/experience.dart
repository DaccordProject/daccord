/// Immutable directory metadata for a reviewed, versioned WASM experience.
class AccordExperienceManifest {
  final String id;
  final String name;
  final String description;
  final String publisher;
  final String version;
  final int hostApi;
  final String runtime;
  final String authority;
  final String sessionMode;
  final int minPlayers;
  final int maxPlayers;
  final int maxSpectators;
  final List<String> platforms;
  final List<String> capabilities;
  final String moduleSha256;

  AccordExperienceManifest.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        name = json['name'] as String,
        description = json['description'] as String,
        publisher = json['publisher'] as String,
        version = json['version'] as String,
        hostApi = json['host_api'] as int,
        runtime = json['runtime'] as String,
        authority = json['authority'] as String,
        sessionMode = json['session_mode'] as String,
        minPlayers = json['min_players'] as int,
        maxPlayers = json['max_players'] as int,
        maxSpectators = json['max_spectators'] as int,
        platforms =
            List.unmodifiable((json['platforms'] as List).cast<String>()),
        capabilities =
            List.unmodifiable((json['capabilities'] as List).cast<String>()),
        moduleSha256 = json['module_sha256'] as String;
}

/// Community-server snapshot. The revision must accompany every mutation.
class AccordExperienceSession {
  final Map<String, dynamic> json;
  AccordExperienceSession.fromJson(Map<String, dynamic> json)
      : json = Map.unmodifiable(json);
  String get id => json['id'] as String;
  String get spaceId => json['space_id'] as String;
  String get gameId => json['game_id'] as String;
  String get version => json['version'] as String;
  String get digest => json['digest'] as String;
  String get mode => json['mode'] as String;
  String get state => json['state'] as String;
  String get hostUserId => json['host_user_id'] as String;
  String? get turnUserId => json['turn_user_id'] as String?;
  int get revision => json['revision'] as int;
  bool get isActive => state == 'lobby' || state == 'running';
  DateTime? get idleExpiresAt {
    final timestamp = json['idle_expires_at'];
    return timestamp is num
        ? DateTime.fromMillisecondsSinceEpoch(timestamp.toInt() * 1000)
        : null;
  }

  List<Map<String, dynamic>> get participants => (json['participants'] as List)
      .map((p) => Map<String, dynamic>.from(p as Map))
      .toList();
  Map<String, dynamic> get game =>
      Map<String, dynamic>.from(json['game'] as Map);
  Map<String, dynamic>? get result => json['result'] == null
      ? null
      : Map<String, dynamic>.from(json['result'] as Map);
}
