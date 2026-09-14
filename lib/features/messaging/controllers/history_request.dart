import 'package:accordkit/accordkit.dart';

/// A request belongs to one provider build/session and one history generation.
typedef HistoryRequest = ({int session, int request});

/// Owns a single history fetch and the live mutations received during it.
/// Supersession, completion and disposal release the journal; it never grows
/// with the lifetime of the message cache. Transport cancellation is optional:
/// callers must check ownership AND client identity before every async write,
/// including failure flags and finally blocks.
class HistoryRequests {
  int _session = 0;
  int _generation = 0;
  HistoryRequest? _active;
  final Map<String, AccordMessage?> _mutations = {};

  bool get isLoading => _active != null;

  void reset() {
    _session++;
    _active = null;
    _mutations.clear();
  }

  HistoryRequest begin() {
    _mutations.clear();
    return _active = (session: _session, request: ++_generation);
  }

  bool owns(HistoryRequest request) => _active == request;

  void finish(HistoryRequest request) {
    if (!owns(request)) return;
    _active = null;
    _mutations.clear();
  }

  void update(AccordMessage message) {
    if (!isLoading) return;
    // A late edit/echo cannot undo a deletion observed during this fetch.
    if (_mutations.containsKey(message.id) && _mutations[message.id] == null) {
      return;
    }
    _mutations[message.id] = message;
  }

  void remove(String id) {
    if (isLoading) _mutations[id] = null;
  }

  /// Retain server ordering, dedupe, then overlay live edits/deletions. Live
  /// rows absent from the snapshot survive in their current display order.
  /// Unknown edits only apply if the snapshot contains their id (deletes fan
  /// out to every open thread, and must not insert unrelated rows there).
  List<AccordMessage> reconcile(
    Iterable<AccordMessage> snapshot,
    Iterable<AccordMessage> current, {
    bool prependLive = false,
  }) {
    final rows = <String, AccordMessage>{};
    for (final message in snapshot) {
      final value = _mutations.containsKey(message.id)
          ? _mutations[message.id]
          : message;
      if (value != null) rows.putIfAbsent(value.id, () => value);
    }
    final live = <String, AccordMessage>{};
    for (final message in current) {
      if (!rows.containsKey(message.id) && _mutations[message.id] != null) {
        live[message.id] = _mutations[message.id]!;
      }
    }
    return prependLive
        ? [...live.values, ...rows.values]
        : [...rows.values, ...live.values];
  }
}
