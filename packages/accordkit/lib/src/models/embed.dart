/// A message embed, with a chainable builder API mirroring the reference
/// client. All setters return `this` so calls can be fluently chained.
class AccordEmbed {
  Object? title;
  Object? type;
  Object? description;
  Object? url;
  Object? timestamp;
  Object? color;
  Object? footer;
  Object? image;
  Object? thumbnail;
  Object? author;
  List<dynamic>? fields;

  AccordEmbed({
    this.title,
    this.type,
    this.description,
    this.url,
    this.timestamp,
    this.color,
    this.footer,
    this.image,
    this.thumbnail,
    this.author,
    this.fields,
  });

  factory AccordEmbed.fromJson(Map<String, dynamic> d) {
    return AccordEmbed(
      title: d['title'],
      type: d['type'],
      description: d['description'],
      url: d['url'],
      timestamp: d['timestamp'],
      color: d['color'],
      footer: d['footer'],
      image: d['image'],
      thumbnail: d['thumbnail'],
      author: d['author'],
      fields: d['fields'] as List<dynamic>?,
    );
  }

  /// Creates an empty embed to start building from.
  static AccordEmbed build() => AccordEmbed();

  Map<String, dynamic> toJson() {
    final d = <String, dynamic>{};
    if (title != null) d['title'] = title;
    if (type != null) d['type'] = type;
    if (description != null) d['description'] = description;
    if (url != null) d['url'] = url;
    if (timestamp != null) d['timestamp'] = timestamp;
    if (color != null) d['color'] = color;
    if (footer != null) d['footer'] = footer;
    if (image != null) d['image'] = image;
    if (thumbnail != null) d['thumbnail'] = thumbnail;
    if (author != null) d['author'] = author;
    if (fields != null) d['fields'] = fields;
    return d;
  }

  AccordEmbed setTitle(String t) {
    title = t;
    return this;
  }

  AccordEmbed setDescription(String desc) {
    description = desc;
    return this;
  }

  AccordEmbed setColor(int c) {
    color = c;
    return this;
  }

  AccordEmbed setUrl(String u) {
    url = u;
    return this;
  }

  AccordEmbed setTimestamp(String ts) {
    timestamp = ts;
    return this;
  }

  AccordEmbed addField(String name, String value, {bool inline = false}) {
    fields ??= [];
    fields!.add({'name': name, 'value': value, 'inline': inline});
    return this;
  }

  AccordEmbed setFooter(String text, {String? iconUrl}) {
    final f = <String, dynamic>{'text': text};
    if (iconUrl != null) f['icon_url'] = iconUrl;
    footer = f;
    return this;
  }

  AccordEmbed setImage(String imageUrl) {
    image = {'url': imageUrl};
    return this;
  }

  AccordEmbed setThumbnail(String thumbnailUrl) {
    thumbnail = {'url': thumbnailUrl};
    return this;
  }

  AccordEmbed setAuthor(String name, {String? authorUrl, String? iconUrl}) {
    final a = <String, dynamic>{'name': name};
    if (authorUrl != null) a['url'] = authorUrl;
    if (iconUrl != null) a['icon_url'] = iconUrl;
    author = a;
    return this;
  }
}
