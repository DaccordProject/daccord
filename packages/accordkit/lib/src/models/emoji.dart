import '../utils/json_utils.dart';

/// A custom emoji. The [id] is null for built-in unicode emoji.
class AccordEmoji {
  String? id;
  String name;
  bool animated;
  bool managed;
  bool available;
  bool requireColons;
  List<String> roleIds;
  String? creatorId;
  String imageUrl;

  AccordEmoji({
    this.id,
    this.name = '',
    this.animated = false,
    this.managed = false,
    this.available = true,
    this.requireColons = true,
    List<String>? roleIds,
    this.creatorId,
    this.imageUrl = '',
  }) : roleIds = roleIds ?? [];

  factory AccordEmoji.fromJson(Map<String, dynamic> d) {
    final rawRoles = asList(d['role_ids'] ?? d['roles']) ?? const [];
    return AccordEmoji(
      id: asStringOrNull(d['id']),
      name: asString(d['name']),
      animated: asBool(d['animated']),
      managed: asBool(d['managed']),
      available: asBool(d['available'], true),
      requireColons: asBool(d['require_colons'], true),
      imageUrl: asString(d['image_url']),
      roleIds: [for (final r in rawRoles) asString(r)],
      creatorId: asStringOrNull(d['creator_id']),
    );
  }

  Map<String, dynamic> toJson() {
    final d = <String, dynamic>{
      'name': name,
      'animated': animated,
      'managed': managed,
      'available': available,
      'require_colons': requireColons,
      'role_ids': roleIds,
    };
    if (id != null) d['id'] = id;
    if (creatorId != null) d['creator_id'] = creatorId;
    if (imageUrl.isNotEmpty) d['image_url'] = imageUrl;
    return d;
  }
}
