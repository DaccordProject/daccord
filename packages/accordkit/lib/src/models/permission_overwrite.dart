import '../utils/json_utils.dart';

/// A channel permission overwrite targeting a role or member.
class AccordPermissionOverwrite {
  String id;
  String type;
  List<dynamic> allow;
  List<dynamic> deny;

  AccordPermissionOverwrite({
    this.id = '',
    this.type = 'role',
    List<dynamic>? allow,
    List<dynamic>? deny,
  })  : allow = allow ?? [],
        deny = deny ?? [];

  factory AccordPermissionOverwrite.fromJson(Map<String, dynamic> d) {
    final rawType = asString(d['type'], 'role');
    return AccordPermissionOverwrite(
      id: asString(d['id']),
      type: rawType == 'member' ? 'user' : rawType,
      allow: asList(d['allow']) ?? [],
      deny: asList(d['deny']) ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'allow': allow,
      'deny': deny,
    };
  }
}
