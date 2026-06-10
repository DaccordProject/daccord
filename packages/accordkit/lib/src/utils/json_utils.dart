/// Internal coercion helpers mirroring the lenient parsing the GDScript
/// reference client performs (snowflakes may arrive as ints or strings,
/// numbers may be ints or doubles, etc.).
library;

/// Coerces [value] to a [String]. Returns [fallback] when null.
String asString(Object? value, [String fallback = '']) {
  if (value == null) return fallback;
  if (value is String) return value;
  return value.toString();
}

/// Coerces [value] to a [String], or null when the value is absent/null.
String? asStringOrNull(Object? value) {
  if (value == null) return null;
  if (value is String) return value;
  return value.toString();
}

/// Coerces [value] to an [int]. Accepts ints, doubles, and numeric strings.
int asInt(Object? value, [int fallback = 0]) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is bool) return value ? 1 : 0;
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

/// Coerces [value] to a [double]. Accepts ints, doubles, and numeric strings.
double asDouble(Object? value, [double fallback = 0.0]) {
  if (value == null) return fallback;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

/// Coerces [value] to a [bool], defaulting to [fallback].
bool asBool(Object? value, [bool fallback = false]) {
  if (value is bool) return value;
  return fallback;
}

/// Returns [value] as a `Map<String, dynamic>` when it is one, else null.
Map<String, dynamic>? asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  return null;
}

/// Returns [value] as a [List] when it is one, else null.
List<dynamic>? asList(Object? value) {
  if (value is List) return value;
  return null;
}

/// Converts a list of model objects exposing `toJson()` into a list of maps.
List<Map<String, dynamic>> toJsonList(Iterable<dynamic> items) {
  return items.map((e) => e.toJson() as Map<String, dynamic>).toList();
}
