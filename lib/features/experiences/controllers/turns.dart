import 'package:accordkit/accordkit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef ExperienceTurnKey = ({String serverKey, String sessionId});
final experienceTurnsProvider =
    NotifierProvider<
      ExperienceTurns,
      Map<ExperienceTurnKey, AccordExperienceSession>
    >(ExperienceTurns.new);

/// Revisions deduplicate gateway deliveries, including dismissed notifications.
/// Both maps are bounded so reconnects cannot accumulate unlimited game state.
class ExperienceTurns
    extends Notifier<Map<ExperienceTurnKey, AccordExperienceSession>> {
  final _revisions = <ExperienceTurnKey, int>{};
  @override
  Map<ExperienceTurnKey, AccordExperienceSession> build() => {};
  void update(String server, String user, AccordExperienceSession session) {
    final key = (serverKey: server, sessionId: session.id);
    if ((_revisions[key] ?? -1) >= session.revision) return;
    _revisions.remove(key);
    _revisions[key] = session.revision;
    if (_revisions.length > 256) _revisions.remove(_revisions.keys.first);
    final next = {...state}..remove(key);
    if (session.state == 'running' && session.turnUserId == user) {
      next[key] = session;
    }
    if (next.length > 128) next.remove(next.keys.first);
    state = Map.unmodifiable(next);
  }

  void dismiss(ExperienceTurnKey key) {
    state = Map.unmodifiable({...state}..remove(key));
  }

  void clearServer(String server) {
    if (!ref.mounted) return;
    _revisions.removeWhere((key, _) => key.serverKey == server);
    state = Map.unmodifiable(
      {...state}..removeWhere((key, _) => key.serverKey == server),
    );
  }
}
