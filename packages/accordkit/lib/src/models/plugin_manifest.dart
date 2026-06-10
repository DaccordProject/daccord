import '../utils/json_utils.dart';

/// Runtime kind of a plugin.
enum PluginRuntime { scripted, native }

/// Lifecycle state of an activity session.
enum SessionState { lobby, running, ended }

/// A participant's role within an activity session.
enum ParticipantRole { spectator, player }

/// A manifest describing a server-installed plugin.
class AccordPluginManifest {
  String id;
  String name;

  /// "activity", "bot", "theme", or "command".
  String type;

  /// "scripted" or "native".
  String runtime;
  String description;
  String? iconUrl;

  /// Lua source URL (scripted plugins).
  String? sourceUrl;

  /// Scene path within the bundle (native plugins).
  String? entryPoint;

  /// "lua" for scripted plugins.
  String format;
  int bundleSize;

  /// "sha256:<hex>" (native plugins).
  String bundleHash;

  /// 0 = unlimited.
  int maxParticipants;

  /// 0 = unlimited; -1 = no spectators.
  int maxSpectators;

  /// Max user-supplied file size in bytes (0 = no file sharing).
  int maxFileSize;
  String version;
  List<dynamic> permissions;
  bool lobby;
  List<dynamic> dataTopics;
  bool signed;
  String? signature;

  /// `[width, height]` canvas size for scripted plugins.
  List<int> canvasSize;

  /// `{leaderboards: [...], achievements: [...], ...}`.
  Map<String, dynamic> services;

  AccordPluginManifest({
    this.id = '',
    this.name = '',
    this.type = '',
    this.runtime = '',
    this.description = '',
    this.iconUrl,
    this.sourceUrl,
    this.entryPoint,
    this.format = '',
    this.bundleSize = 0,
    this.bundleHash = '',
    this.maxParticipants = 0,
    this.maxSpectators = 0,
    this.maxFileSize = 0,
    this.version = '',
    List<dynamic>? permissions,
    this.lobby = false,
    List<dynamic>? dataTopics,
    this.signed = false,
    this.signature,
    List<int>? canvasSize,
    Map<String, dynamic>? services,
  })  : permissions = permissions ?? [],
        dataTopics = dataTopics ?? [],
        canvasSize = canvasSize ?? [480, 360],
        services = services ?? {};

  factory AccordPluginManifest.fromJson(Map<String, dynamic> d) {
    final m = AccordPluginManifest(
      id: asString(d['id']),
      name: asString(d['name']),
      type: asString(d['type']),
      runtime: asString(d['runtime']),
      description: asString(d['description']),
      iconUrl: asStringOrNull(d['icon_url']),
      sourceUrl: asStringOrNull(d['source_url']),
      entryPoint: asStringOrNull(d['entry_point']),
      format: asString(d['format']),
      bundleSize: asInt(d['bundle_size']),
      bundleHash: asString(d['bundle_hash']),
      maxParticipants: asInt(d['max_participants']),
      maxSpectators: asInt(d['max_spectators']),
      maxFileSize: asInt(d['max_file_size']),
      version: asString(d['version']),
      permissions: asList(d['permissions']) ?? [],
      lobby: asBool(d['lobby']),
      dataTopics: asList(d['data_topics']) ?? [],
      signed: asBool(d['signed']),
      signature: asStringOrNull(d['signature']),
      services: asMap(d['services']) ?? {},
    );

    final rawCanvas = asList(d['canvas_size']);
    if (rawCanvas != null && rawCanvas.length >= 2) {
      m.canvasSize = [asInt(rawCanvas[0]), asInt(rawCanvas[1])];
    } else if (d.containsKey('canvas_width') &&
        d.containsKey('canvas_height')) {
      m.canvasSize = [asInt(d['canvas_width']), asInt(d['canvas_height'])];
    }
    return m;
  }

  Map<String, dynamic> toJson() {
    final d = <String, dynamic>{
      'id': id,
      'name': name,
      'type': type,
      'runtime': runtime,
      'description': description,
      'bundle_size': bundleSize,
      'bundle_hash': bundleHash,
      'max_participants': maxParticipants,
      'max_spectators': maxSpectators,
      'max_file_size': maxFileSize,
      'version': version,
      'permissions': permissions,
      'lobby': lobby,
      'data_topics': dataTopics,
      'signed': signed,
      'canvas_size': canvasSize,
    };
    if (services.isNotEmpty) d['services'] = services;
    if (format.isNotEmpty) d['format'] = format;
    if (iconUrl != null) d['icon_url'] = iconUrl;
    if (sourceUrl != null) d['source_url'] = sourceUrl;
    if (entryPoint != null) d['entry_point'] = entryPoint;
    if (signature != null) d['signature'] = signature;
    return d;
  }
}
