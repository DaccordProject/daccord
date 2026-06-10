import '../utils/json_utils.dart';

/// An application (bot) registered on an instance.
class AccordApplication {
  String id;
  String name;
  Object? icon;
  String description;
  bool botPublic;
  String ownerId;
  int flags;

  AccordApplication({
    this.id = '',
    this.name = '',
    this.icon,
    this.description = '',
    this.botPublic = false,
    this.ownerId = '',
    this.flags = 0,
  });

  factory AccordApplication.fromJson(Map<String, dynamic> d) {
    final rawOwner = asMap(d['owner']);
    return AccordApplication(
      id: asString(d['id']),
      name: asString(d['name']),
      icon: d['icon'],
      description: asString(d['description']),
      botPublic: asBool(d['bot_public']),
      ownerId:
          rawOwner != null ? asString(rawOwner['id']) : asString(d['owner_id']),
      flags: asInt(d['flags']),
    );
  }

  Map<String, dynamic> toJson() {
    final d = <String, dynamic>{
      'id': id,
      'name': name,
      'description': description,
      'bot_public': botPublic,
      'owner_id': ownerId,
      'flags': flags,
    };
    if (icon != null) d['icon'] = icon;
    return d;
  }
}
