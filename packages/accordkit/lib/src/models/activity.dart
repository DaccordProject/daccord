import '../utils/json_utils.dart';

/// An activity entry within a presence (e.g. "Playing X").
class AccordActivity {
  String name;
  String type;
  Object? url;
  Object? state;
  Object? details;
  Object? timestamps;
  Object? assets;

  AccordActivity({
    this.name = '',
    this.type = 'playing',
    this.url,
    this.state,
    this.details,
    this.timestamps,
    this.assets,
  });

  factory AccordActivity.fromJson(Map<String, dynamic> d) {
    return AccordActivity(
      name: asString(d['name']),
      type: asString(d['type'], 'playing'),
      url: d['url'],
      state: d['state'],
      details: d['details'],
      timestamps: d['timestamps'],
      assets: d['assets'],
    );
  }

  Map<String, dynamic> toJson() {
    final d = <String, dynamic>{
      'name': name,
      'type': type,
    };
    if (url != null) d['url'] = url;
    if (state != null) d['state'] = state;
    if (details != null) d['details'] = details;
    if (timestamps != null) d['timestamps'] = timestamps;
    if (assets != null) d['assets'] = assets;
    return d;
  }
}
