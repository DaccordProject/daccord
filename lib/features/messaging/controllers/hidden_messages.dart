import 'package:bonfire/features/profiles/services/profile_store.dart';
import 'package:hive_ce/hive.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'hidden_messages.g.dart';

/// Key under which the hidden set is persisted in the active profile's settings
/// box. Deliberately not part of [AccordSettings]: this is a moderation record
/// rather than a preference, and it must survive even if settings are reset.
const String hiddenMessagesKey = 'reported-hidden-message-ids';

/// Messages the user has reported and therefore no longer wants to see.
///
/// Reporting content in a space hands it to that space's moderators, but
/// nothing about their decision is instant — and a direct message has no
/// moderator at all. Either way the reporter should stop seeing what they just
/// flagged, so the pane filters these out locally, on this device, for good
/// (App Review 1.2, #290).
@Riverpod(keepAlive: true)
class HiddenMessagesController extends _$HiddenMessagesController {
  /// The settings box, or null when storage isn't up (widget tests that skip
  /// Hive, and the window before bootstrap finishes). Reading it defensively
  /// keeps a hidden-message lookup from breaking every pane that watches it.
  Box? get _box => Hive.isBoxOpen(ProfileStore.activeSettingsBoxName)
      ? ProfileStore.settingsBox
      : null;

  @override
  Set<String> build() {
    final stored = _box?.get(hiddenMessagesKey);
    if (stored is! List) return const {};
    return {
      for (final id in stored)
        if (id is String && id.isNotEmpty) id,
    };
  }

  /// Hides [messageId] and persists the change. No-op if already hidden.
  Future<void> hide(String messageId) async {
    if (messageId.isEmpty || state.contains(messageId)) return;
    state = {...state, messageId};
    await _persist();
  }

  /// Restores [messageId]. Nothing in the UI calls this yet — it exists so a
  /// mistaken report is recoverable rather than permanent.
  Future<void> unhide(String messageId) async {
    if (!state.contains(messageId)) return;
    state = {...state}..remove(messageId);
    await _persist();
  }

  Future<void> _persist() async =>
      await _box?.put(hiddenMessagesKey, state.toList());
}
