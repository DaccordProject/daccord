import 'package:accordkit/accordkit.dart';

/// Actor token for the signed-in user in reaction journals and reactor sets.
/// Own reactions arrive either from an optimistic toggle (no user id) or from
/// a gateway echo (bare or federated id), so they are keyed on this token.
const selfReactor = '\u0000self';

/// A live reaction change received while a snapshot of the same message was
/// being fetched. Changes are recorded per user so they can be applied to the
/// snapshot idempotently: applying one the snapshot already includes is a
/// no-op, so nothing is counted twice.
sealed class ReactionOp {
  const ReactionOp();

  /// Whether this op touches the emoji with canonical key [key].
  bool touches(String key);
}

/// [actor] added or removed their [key] reaction. [actor] is [selfReactor] for
/// the signed-in user, and null if the event did not name the user.
final class ReactionDelta extends ReactionOp {
  const ReactionDelta({
    required this.key,
    required this.emoji,
    required this.actor,
    required this.added,
  });

  final String key;
  final Map<String, dynamic> emoji;
  final String? actor;
  final bool added;

  @override
  bool touches(String key) => key == this.key;
}

/// Every reaction ([key] null) or every [key] reaction was removed.
final class ReactionClear extends ReactionOp {
  const ReactionClear([this.key]);

  final String? key;

  @override
  bool touches(String key) => this.key == null || this.key == key;
}

/// An emoji whose other-user changes cannot be settled against an aggregate
/// count, because the aggregate does not say who reacted.
typedef PendingReactors = ({String key, Map<String, dynamic> emoji});

/// Replays [ops], in order, onto [message]'s server aggregates.
///
/// Clears and the signed-in user's own changes are applied directly: the
/// aggregate's `includesMe` says whether our reaction is already counted, so
/// they are idempotent. Another user's change is ambiguous against a bare
/// count (the snapshot may or may not already include it), so it is not
/// applied here. Instead its emoji is returned so the caller can settle it
/// against the reactor list ([replayOntoReactors]). Until then the server
/// count stands, which may briefly lag but never double-counts. Emojis the ops
/// do not touch keep their server aggregates.
List<PendingReactors> replayReactionOps(
  AccordMessage message,
  Iterable<ReactionOp> ops,
  String Function(AccordReaction) keyOf,
) {
  // Fresh objects: never mutate aggregates a published state may share.
  final reactions = [
    for (final r in message.reactions ?? const <AccordReaction>[])
      AccordReaction(
        emoji: Map.of(r.emoji),
        count: r.count,
        includesMe: r.includesMe,
      ),
  ];
  final pending = <String, Map<String, dynamic>>{};
  for (final op in ops) {
    switch (op) {
      case ReactionClear(key: null):
        reactions.clear();
        pending.clear();
      case ReactionClear(:final key?):
        reactions.removeWhere((r) => keyOf(r) == key);
        pending.remove(key);
      case ReactionDelta(:final key, :final emoji, actor: selfReactor):
        final index = reactions.indexWhere((r) => keyOf(r) == key);
        final r = index < 0 ? null : reactions[index];
        final counted = r?.includesMe ?? false;
        if (op.added && !counted) {
          if (r == null) {
            reactions.add(
              AccordReaction(emoji: Map.of(emoji), count: 1, includesMe: true),
            );
          } else {
            r
              ..count += 1
              ..includesMe = true;
          }
        } else if (!op.added && counted) {
          r!
            ..count = r.count > 0 ? r.count - 1 : 0
            ..includesMe = false;
          if (r.count <= 0) reactions.removeAt(index);
        }
      case ReactionDelta(:final key, :final emoji):
        pending[key] = emoji;
    }
  }
  message.reactions = reactions;
  return [for (final e in pending.entries) (key: e.key, emoji: e.value)];
}

/// Applies [ops] for [key], in order, to a reactor set fetched from the server
/// (user ids, with the signed-in user as [selfReactor]). Set operations are
/// idempotent per user: an add the listing already includes, or a removal it
/// already reflects, changes nothing.
Set<String> replayOntoReactors(
  Set<String> reactors,
  Iterable<ReactionOp> ops,
  String key,
) {
  final users = {...reactors};
  for (final op in ops) {
    if (!op.touches(key)) continue;
    switch (op) {
      case ReactionClear():
        users.clear();
      case ReactionDelta(:final actor?, :final added):
        added ? users.add(actor) : users.remove(actor);
      case ReactionDelta():
        // An unnamed actor cannot be matched to a listing entry; the listing
        // (or the next event for this emoji) is left to account for it.
        break;
    }
  }
  return users;
}
