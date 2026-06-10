import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Builds `multipart/form-data` request bodies for file uploads and mixed
/// payloads. Add parts with [addField]/[addJson]/[addFile], then [build] the
/// final byte body and send it with [contentType].
class MultipartForm {
  final String _boundary;
  final List<Uint8List> _parts = [];

  MultipartForm({String? boundary})
      : _boundary = boundary ?? '----AccordForm${Random().nextInt(1 << 31)}';

  static const List<int> _crlf = [13, 10]; // "\r\n"

  /// Adds a plain text field.
  void addField(String name, String value) {
    final header =
        '--$_boundary\r\nContent-Disposition: form-data; name="$name"\r\n\r\n';
    final part = BytesBuilder()
      ..add(utf8.encode(header))
      ..add(utf8.encode(value))
      ..add(_crlf);
    _parts.add(part.toBytes());
  }

  /// Adds a JSON field. [data] is encoded with [jsonEncode].
  void addJson(String name, Object? data) {
    final jsonStr = jsonEncode(data);
    final header = '--$_boundary\r\nContent-Disposition: form-data; '
        'name="$name"\r\nContent-Type: application/json\r\n\r\n';
    final part = BytesBuilder()
      ..add(utf8.encode(header))
      ..add(utf8.encode(jsonStr))
      ..add(_crlf);
    _parts.add(part.toBytes());
  }

  /// Adds a binary file part.
  void addFile(
    String name,
    String filename,
    List<int> content, {
    String contentType = 'application/octet-stream',
  }) {
    final header = '--$_boundary\r\nContent-Disposition: form-data; '
        'name="$name"; filename="$filename"\r\nContent-Type: $contentType\r\n\r\n';
    final part = BytesBuilder()
      ..add(utf8.encode(header))
      ..add(content)
      ..add(_crlf);
    _parts.add(part.toBytes());
  }

  /// The `Content-Type` header value, including the boundary.
  String contentType() => 'multipart/form-data; boundary=$_boundary';

  /// Assembles all parts plus the closing boundary into the final body.
  Uint8List build() {
    final result = BytesBuilder();
    for (final part in _parts) {
      result.add(part);
    }
    result.add(utf8.encode('--$_boundary--\r\n'));
    return result.toBytes();
  }
}
