import '../utils/json_utils.dart';

/// A soundboard sound.
class AccordSound {
  String? id;
  String name;
  String audioUrl;
  double volume;
  String? creatorId;
  String createdAt;
  String updatedAt;

  AccordSound({
    this.id,
    this.name = '',
    this.audioUrl = '',
    this.volume = 1.0,
    this.creatorId,
    this.createdAt = '',
    this.updatedAt = '',
  });

  factory AccordSound.fromJson(Map<String, dynamic> d) {
    return AccordSound(
      id: asStringOrNull(d['id']),
      name: asString(d['name']),
      audioUrl: asString(d['audio_url']),
      volume: asDouble(d['volume'], 1.0),
      creatorId: asStringOrNull(d['creator_id']),
      createdAt: asString(d['created_at']),
      updatedAt: asString(d['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    final d = <String, dynamic>{
      'name': name,
      'audio_url': audioUrl,
      'volume': volume,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
    if (id != null) d['id'] = id;
    if (creatorId != null) d['creator_id'] = creatorId;
    return d;
  }
}
