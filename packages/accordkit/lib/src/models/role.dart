import '../utils/json_utils.dart';

/// A role within a space.
class AccordRole {
  String id;
  String name;
  int color;
  bool hoist;
  Object? icon;
  int position;
  List<dynamic> permissions;
  bool managed;
  bool mentionable;

  AccordRole({
    this.id = '',
    this.name = '',
    this.color = 0,
    this.hoist = false,
    this.icon,
    this.position = 0,
    List<dynamic>? permissions,
    this.managed = false,
    this.mentionable = false,
  }) : permissions = permissions ?? [];

  factory AccordRole.fromJson(Map<String, dynamic> d) {
    return AccordRole(
      id: asString(d['id']),
      name: asString(d['name']),
      color: asInt(d['color']),
      hoist: asBool(d['hoist']),
      icon: d['icon'],
      position: asInt(d['position']),
      permissions: asList(d['permissions']) ?? [],
      managed: asBool(d['managed']),
      mentionable: asBool(d['mentionable']),
    );
  }

  Map<String, dynamic> toJson() {
    final d = <String, dynamic>{
      'id': id,
      'name': name,
      'color': color,
      'hoist': hoist,
      'position': position,
      'permissions': permissions,
      'managed': managed,
      'mentionable': mentionable,
    };
    if (icon != null) d['icon'] = icon;
    return d;
  }
}
