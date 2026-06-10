import 'accord_rest.dart';
import 'rest_result.dart';

/// Cursor-based pagination helper wrapping a single page of items. Call [next]
/// to fetch the following page using the same path, query, and model class.
class AccordPaginator {
  List<dynamic> items;
  bool hasMore = false;
  String _after = '';

  final AccordRest _rest;
  final String _path;
  final Map<String, dynamic> _query;
  final Object Function(Map<String, dynamic>)? _fromJson;

  AccordPaginator._(
    this._rest,
    this._path,
    this._query,
    this._fromJson, {
    List<dynamic>? items,
  }) : items = items ?? [];

  /// Builds a paginator from a [RestResult]. When [fromJson] is provided, Map
  /// items are deserialized into model instances.
  static AccordPaginator fromResult(
    RestResult result,
    AccordRest rest,
    String path,
    Map<String, dynamic> query, {
    Object Function(Map<String, dynamic>)? fromJson,
  }) {
    final p = AccordPaginator._(
        rest, path, Map<String, dynamic>.from(query), fromJson);
    if (result.ok) {
      final data = result.data;
      if (data is List) {
        if (fromJson != null) {
          p.items = [
            for (final item in data)
              if (item is Map<String, dynamic>) fromJson(item) else item,
          ];
        } else {
          p.items = data;
        }
      }
      p.hasMore = result.hasMore;
      p._after = (result.cursor['after'] ?? '').toString();
    }
    return p;
  }

  /// Fetches the next page using the stored cursor, returning a new paginator.
  Future<AccordPaginator> next() async {
    final query = Map<String, dynamic>.from(_query)..['after'] = _after;
    final result = await _rest.makeRequest('GET', _path, query: query);
    return fromResult(result, _rest, _path, query, fromJson: _fromJson);
  }
}
