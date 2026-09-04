/// Identity-keyed list helpers for the per-feature cache controllers.
///
/// Centralizes the `indexWhere((x) => x.id == y.id)` replace-or-append and the
/// `where((x) => x.id != id)` drop that were hand-rolled across the channel,
/// emoji, message, space, DM-channel and connection controllers.
extension UpsertById<T> on List<T> {
  /// Returns a new list with [item] replacing the element whose id equals
  /// `id(item)`, or appended when no such element exists.
  List<T> upsertById(T item, Object? Function(T) id) {
    final key = id(item);
    final copy = [...this];
    final index = copy.indexWhere((e) => id(e) == key);
    if (index >= 0) {
      copy[index] = item;
    } else {
      copy.add(item);
    }
    return copy;
  }

  /// Returns a new list with [item] replacing the element whose id equals
  /// `id(item)`, or `null` when no such element exists — so a controller can
  /// ignore an update for an id it never loaded without touching its state.
  List<T>? replaceById(T item, Object? Function(T) id) {
    final key = id(item);
    final index = indexWhere((e) => id(e) == key);
    if (index < 0) return null;
    final copy = [...this];
    copy[index] = item;
    return copy;
  }

  /// Returns a new list with every element whose id equals [id] removed.
  List<T> removeById(Object? id, Object? Function(T) idOf) =>
      where((e) => idOf(e) != id).toList();
}
