import 'package:bonfire/features/channels/controllers/read_state.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'global_unread.g.dart';

/// App-wide unread roll-up: every connected server's [ReadStateSnapshot] folded
/// into the two numbers a badge needs.
///
/// [mentionCount] is what gets rendered as a number (matching Discord/Slack,
/// which badge mentions rather than total unread, so the digit stays
/// meaningful); [hasUnread] is the "there's something new" dot for unread with
/// no mentions.
class GlobalUnread {
  const GlobalUnread({this.hasUnread = false, this.mentionCount = 0});

  /// Nothing unread anywhere — the badge should be cleared.
  static const GlobalUnread none = GlobalUnread();

  /// True when at least one *visible* (non-muted) channel is unread, on any
  /// connection. Always true when [mentionCount] > 0.
  final bool hasUnread;

  /// Total pending mentions across every connection, muted channels excluded.
  final int mentionCount;

  bool get isEmpty => !hasUnread && mentionCount == 0;

  @override
  bool operator ==(Object other) =>
      other is GlobalUnread &&
      other.hasUnread == hasUnread &&
      other.mentionCount == mentionCount;

  @override
  int get hashCode => Object.hash(hasUnread, mentionCount);

  @override
  String toString() =>
      'GlobalUnread(hasUnread: $hasUnread, mentionCount: $mentionCount)';
}

/// Folds [snapshots] (one per connected server) into a single [GlobalUnread],
/// dropping everything the user silenced.
///
/// The mute policy is *not* reimplemented here: it defers to
/// [UnreadIndicatorGate.countsTowardSpace] — the same gate the space rail uses
/// — so a taskbar badge can never disagree with the in-app indicators. DM
/// entries carry no [ReadEntry.spaceId] and so can't be space-muted; only their
/// per-channel level applies.
///
/// [mutedSpaces] mirrors `AccordSettings.mutedSpaces` and [channelLevels]
/// mirrors `AccordSettings.channelNotifications`.
GlobalUnread foldGlobalUnread(
  Iterable<ReadStateSnapshot> snapshots, {
  Iterable<String> mutedSpaces = const <String>[],
  Map<String, String> channelLevels = const <String, String>{},
}) {
  final muted = mutedSpaces is Set<String> ? mutedSpaces : mutedSpaces.toSet();
  var hasUnread = false;
  var mentions = 0;
  for (final snapshot in snapshots) {
    for (final entry in snapshot.entries.values) {
      final spaceId = entry.spaceId;
      if (!UnreadIndicatorGate.countsTowardSpace(
        spaceMuted: spaceId != null && muted.contains(spaceId),
        channelLevel: channelLevels[entry.channelId],
      )) {
        continue;
      }
      hasUnread = true;
      mentions += entry.mentions;
    }
  }
  return GlobalUnread(hasUnread: hasUnread, mentionCount: mentions);
}

/// The unread state of the *whole app*, across every connected server.
///
/// Drives the desktop taskbar/dock badge (`TaskbarBadgeController`) and is
/// reusable for a future tray icon or mobile app-icon badge. Kept alive because
/// its consumers are services, not widgets, and it must keep updating while the
/// window is minimised.
@Riverpod(keepAlive: true)
GlobalUnread globalUnread(Ref ref) {
  final connections = ref.watch(
    connectionsControllerProvider.select((s) => s.connections),
  );
  // Watch only the two settings slices the mute gate reads, so an unrelated
  // settings write (a draft keystroke) can't churn the badge.
  final mutedSpaces = ref.watch(
    settingsControllerProvider.select((s) => s.mutedSpaces),
  );
  final channelLevels = ref.watch(
    settingsControllerProvider.select((s) => s.channelNotifications),
  );
  return foldGlobalUnread(
    [
      for (final connection in connections)
        ref.watch(readStateControllerProvider(connection.key)),
    ],
    mutedSpaces: mutedSpaces,
    channelLevels: channelLevels,
  );
}
