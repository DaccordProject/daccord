import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/messaging/controllers/reaction_journal.dart';

/// A request belongs to one provider build/session and one history generation.
typedef HistoryRequest = ({int session, int request});

/// What happened to one message id while a history fetch was in flight.
class _Mutation {
  /// Deleted during the fetch: the snapshot row must not come back.
  bool deleted = false;

  /// Created during the fetch: survives even if the snapshot predates it.
  bool created = false;

  /// A whole-row create/edit received during the fetch. It is at least as new
  /// as the snapshot row, so it replaces it.
  AccordMessage? replacement;

  /// Field-level changes (pin) received during the fetch. They are replayed
  /// onto whichever row wins, so a pin arriving mid-reload does not drag the
  /// pre-disconnect copy of the message back over the fresh one. Each patch
  /// sets a field to a value, so re-applying it is harmless.
  final List<void Function(AccordMessage)> patches = [];

  /// Per-user reaction changes received during the fetch, in arrival order.
  /// See [replayReactionOps].
  final List<ReactionOp> reactions = [];
}

/// Owns a single history fetch and the live mutations received during it.
/// Supersession, completion and disposal release the journal; it never grows
/// with the lifetime of the message cache. Transport cancellation is optional:
/// callers must check ownership AND client identity before every async write,
/// including failure flags and finally blocks.
class HistoryRequests {
  int _session = 0;
  int _generation = 0;
  HistoryRequest? _active;
  final Map<String, _Mutation> _mutations = {};

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

  /// Returns the journal entry for [id], or null when nothing should be
  /// recorded (no fetch in flight, or the id was already deleted during it:
  /// a late edit/echo cannot undo that deletion).
  _Mutation? _entry(String id) {
    if (!isLoading) return null;
    final entry = _mutations.putIfAbsent(id, _Mutation.new);
    return entry.deleted ? null : entry;
  }

  /// A message created live (gateway create / send result).
  void add(AccordMessage message) {
    final entry = _entry(message.id);
    if (entry == null) return;
    entry
      ..created = true
      ..replacement = message
      ..patches.clear();
  }

  /// A whole-row edit received live.
  void update(AccordMessage message) {
    final entry = _entry(message.id);
    if (entry == null) return;
    entry
      ..replacement = message
      ..patches.clear();
  }

  /// A field-level change (pin) received live. [apply] must set
  /// fields to fixed values rather than compute deltas, so it is idempotent.
  void patch(String id, void Function(AccordMessage) apply) {
    _entry(id)?.patches.add(apply);
  }

  /// A reaction change received live. Recorded even for ids not in the cache
  /// yet: the snapshot may contain the message.
  void recordReaction(String id, ReactionOp op) {
    _entry(id)?.reactions.add(op);
  }

  /// The reaction changes to replay onto the row for [id] (empty when none).
  List<ReactionOp> reactionOps(String id) {
    final entry = _mutations[id];
    return entry == null || entry.deleted ? const [] : entry.reactions;
  }

  void remove(String id) {
    if (isLoading) _mutations[id] = _Mutation()..deleted = true;
  }

  /// Retain server ordering, dedupe, then overlay live edits/deletions and
  /// replay field patches. Rows created live that are absent from the snapshot
  /// survive in their current display order. Edits and patches only apply if
  /// the snapshot contains their id (deletes fan out to every open thread, and
  /// must not insert unrelated rows there).
  List<AccordMessage> reconcile(
    Iterable<AccordMessage> snapshot,
    Iterable<AccordMessage> current, {
    bool prependLive = false,
  }) {
    final rows = <String, AccordMessage>{};
    for (final message in snapshot) {
      final entry = _mutations[message.id];
      if (entry == null) {
        rows.putIfAbsent(message.id, () => message);
        continue;
      }
      if (entry.deleted) continue;
      final value = entry.replacement ?? message;
      for (final apply in entry.patches) {
        apply(value);
      }
      rows.putIfAbsent(value.id, () => value);
    }
    final live = <String, AccordMessage>{};
    for (final message in current) {
      final entry = _mutations[message.id];
      if (rows.containsKey(message.id) || entry == null) continue;
      if (entry.deleted || !entry.created) continue;
      live[message.id] = message;
    }
    return prependLive
        ? [...live.values, ...rows.values]
        : [...rows.values, ...live.values];
  }
}
