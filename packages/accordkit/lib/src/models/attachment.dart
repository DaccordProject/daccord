import '../utils/json_utils.dart';

/// A file attachment on a message.
class AccordAttachment {
  String id;
  String filename;
  String? description;
  String? contentType;
  int size;
  String url;
  Object? width;
  Object? height;

  AccordAttachment({
    this.id = '',
    this.filename = '',
    this.description,
    this.contentType,
    this.size = 0,
    this.url = '',
    this.width,
    this.height,
  });

  factory AccordAttachment.fromJson(Map<String, dynamic> d) {
    return AccordAttachment(
      id: asString(d['id']),
      filename: asString(d['filename']),
      description: d['description'] as String?,
      contentType: d['content_type'] as String?,
      size: asInt(d['size']),
      url: asString(d['url']),
      width: d['width'],
      height: d['height'],
    );
  }

  Map<String, dynamic> toJson() {
    final d = <String, dynamic>{
      'id': id,
      'filename': filename,
      'size': size,
      'url': url,
    };
    if (description != null) d['description'] = description;
    if (contentType != null) d['content_type'] = contentType;
    if (width != null) d['width'] = width;
    if (height != null) d['height'] = height;
    return d;
  }
}
