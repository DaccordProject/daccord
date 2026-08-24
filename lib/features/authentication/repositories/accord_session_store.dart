import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/profiles/services/profile_store.dart';
import 'package:hive_ce/hive.dart';

/// Hive-backed persistence for Accord sessions: the active-session pointer plus
/// the saved-account list behind the account switcher. Extracted from
/// [AccordAuth] so the auth notifier holds only the auth flows and live
/// connection orchestration; this class knows nothing about clients or state.
///
/// The operations are deliberately granular (read/delete the active pointer
/// separately from the account list) so [AccordAuth] keeps its exact
/// orchestration order across logout/remove/switch flows.
class AccordSessionStore {
  static const _sessionKey = 'session';
  static const _accountsKey = 'accounts';

  Future<Box> _box() => Hive.openBox(ProfileStore.activeSessionBoxName);

  /// Persists [session] as the active session and upserts it into the saved
  /// account list (keyed by user + server). Enforces one account per server:
  /// any other saved account on the same server is dropped, so signing in as a
  /// new user replaces the old one rather than leaving a stale duplicate.
  Future<void> persist(AccordSession session) async {
    if (session.isGuest || session.isExpired) return;
    final box = await _box();
    await box.put(_sessionKey, session.toJson());
    final accounts = _accountsFrom(box);
    final key = session.key;
    accounts.removeWhere((k, v) {
      if (k == key || v is! Map) return false;
      try {
        final other = AccordSession.fromJson(Map<String, dynamic>.from(v));
        return other.server.baseUrl == session.server.baseUrl;
      } catch (_) {
        return false;
      }
    });
    accounts[key] = session.toJson();
    await box.put(_accountsKey, accounts);
  }

  /// Records [session] as the persisted *active* pointer without touching the
  /// saved-accounts list (already persisted when first added).
  Future<void> persistActive(AccordSession session) async {
    if (session.isGuest || session.isExpired) return;
    final box = await _box();
    await box.put(_sessionKey, session.toJson());
  }

  /// Active session eligible for restart. Guest or expired credentials are
  /// deleted defensively even if an older client wrote them.
  Future<AccordSession?> readRestorableActive() async {
    final box = await _box();
    final raw = box.get(_sessionKey);
    if (raw == null) return null;
    final session = AccordSession.fromJson(
      Map<String, dynamic>.from(raw as Map),
    );
    if (session.isGuest || session.isExpired) {
      await box.delete(_sessionKey);
      return null;
    }
    return session;
  }

  /// The raw stored active-session value (a JSON map when present). Callers own
  /// parsing so they keep their own corrupt-entry semantics.
  Future<Object?> readActiveRaw() async => (await _box()).get(_sessionKey);

  /// Deletes the active-session pointer.
  Future<void> deleteActive() async => (await _box()).delete(_sessionKey);

  /// Removes the saved account [key] from the account list.
  Future<void> removeAccount(String key) async {
    final box = await _box();
    final accounts = _accountsFrom(box);
    accounts.remove(key);
    await box.put(_accountsKey, accounts);
  }

  /// All saved accounts, for the switcher UI. Malformed entries are skipped.
  Future<List<AccordSession>> listAccounts() async {
    final accounts = _accountsFrom(await _box());
    final result = <AccordSession>[];
    for (final raw in accounts.values) {
      if (raw is! Map) continue;
      try {
        final session = AccordSession.fromJson(Map<String, dynamic>.from(raw));
        if (!session.isGuest && !session.isExpired) result.add(session);
      } catch (_) {
        // Skip malformed saved accounts.
      }
    }
    return result;
  }

  Map<String, dynamic> _accountsFrom(Box box) {
    final raw = box.get(_accountsKey);
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }
}
