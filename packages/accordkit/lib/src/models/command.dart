import '../utils/json_utils.dart';

/// An application (slash) command.
class AccordCommand {
  String id;
  String applicationId;
  String? spaceId;
  String name;
  String description;
  Object? options;
  String type;

  AccordCommand({
    this.id = '',
    this.applicationId = '',
    this.spaceId,
    this.name = '',
    this.description = '',
    this.options,
    this.type = 'chat_input',
  });

  factory AccordCommand.fromJson(Map<String, dynamic> d) {
    return AccordCommand(
      id: asString(d['id']),
      applicationId: asString(d['application_id']),
      spaceId: asStringOrNull(d['space_id'] ?? d['guild_id']),
      name: asString(d['name']),
      description: asString(d['description']),
      options: d['options'],
      type: asString(d['type'], 'chat_input'),
    );
  }

  Map<String, dynamic> toJson() {
    final d = <String, dynamic>{
      'id': id,
      'application_id': applicationId,
      'name': name,
      'description': description,
      'type': type,
    };
    if (spaceId != null) d['space_id'] = spaceId;
    if (options != null) d['options'] = options;
    return d;
  }
}
