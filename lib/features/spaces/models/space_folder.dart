/// A user-defined folder grouping space icons in the rail. Mirrors the
/// reference client's `Config` `folders` / `folder_name_colors` entries.
class SpaceFolder {
  const SpaceFolder({
    required this.id,
    this.name = '',
    this.color,
    this.collapsed = false,
    this.spaceIds = const [],
  });

  /// Stable folder id (used for persistence and drag targets).
  final String id;

  /// Optional folder name (shown when expanded / as a tooltip).
  final String name;

  /// Optional ARGB color override for the folder tile; null = default.
  final int? color;

  /// Whether the folder is collapsed (shows a stacked preview instead of its
  /// expanded space icons).
  final bool collapsed;

  /// Ordered space ids contained in this folder.
  final List<String> spaceIds;

  SpaceFolder copyWith({
    String? name,
    int? color,
    bool clearColor = false,
    bool? collapsed,
    List<String>? spaceIds,
  }) => SpaceFolder(
    id: id,
    name: name ?? this.name,
    color: clearColor ? null : (color ?? this.color),
    collapsed: collapsed ?? this.collapsed,
    spaceIds: spaceIds ?? this.spaceIds,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (color != null) 'color': color,
    'collapsed': collapsed,
    'spaceIds': spaceIds,
  };

  static SpaceFolder fromJson(Map<dynamic, dynamic> json) => SpaceFolder(
    id: (json['id'] ?? '').toString(),
    name: (json['name'] ?? '').toString(),
    color: (json['color'] as num?)?.toInt(),
    collapsed: json['collapsed'] as bool? ?? false,
    spaceIds: [
      for (final s in (json['spaceIds'] as List? ?? const [])) s.toString(),
    ],
  );
}
