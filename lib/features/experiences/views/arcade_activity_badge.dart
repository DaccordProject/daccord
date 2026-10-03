import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef ArcadeKey = ({String serverKey, String spaceId});

/// A shared count for the sidebar and Arcade page. Private lobbies are counted
/// only for members who can see them; server simulation ticks are not activity.
final arcadeActivityProvider = StreamProvider.autoDispose
    .family<int, ArcadeKey>((ref, key) {
      final client = ref.watchAccordClientFor(key.serverKey);
      final stream = StreamController<int>();
      var disposed = false;
      var refreshing = false;
      Future<void> refresh() async {
        if (disposed || refreshing || client == null) return;
        refreshing = true;
        try {
          final result = await client.experiences.arcade(key.spaceId);
          if (!result.ok || result.data is! Map) {
            throw StateError('Active game count unavailable');
          }
          final data = result.data as Map;
          var count = (data['active_sessions'] as num?)?.toInt();
          // Older servers expose sessions without the summary count.
          if (count == null) {
            if (data['visible'] != true) {
              count = 0;
            } else {
              final sessions = await client.experiences.sessions(key.spaceId);
              if (!sessions.ok || sessions.data is! List) {
                throw StateError('Active game count unavailable');
              }
              count = (sessions.data as List)
                  .whereType<AccordExperienceSession>()
                  .where((s) => s.isActive)
                  .length;
            }
          }
          if (!disposed) stream.add(count);
        } catch (error, stack) {
          if (!disposed) stream.addError(error, stack);
        } finally {
          refreshing = false;
        }
      }

      final events = client?.onExperienceSession.listen((event) {
        if (event['space_id'] == key.spaceId) unawaited(refresh());
      });
      final timer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => unawaited(refresh()),
      );
      ref.onDispose(() {
        disposed = true;
        timer.cancel();
        unawaited(events?.cancel());
        unawaited(stream.close());
      });
      unawaited(refresh());
      return stream.stream;
    });

class ArcadeActivityBadge extends ConsumerWidget {
  const ArcadeActivityBadge({
    super.key,
    required this.serverKey,
    required this.spaceId,
  });
  final String serverKey;
  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(
      arcadeActivityProvider((serverKey: serverKey, spaceId: spaceId)),
    );
    final count = activity.asData?.value;
    final label = count == null ? (activity.hasError ? '—' : '…') : '$count';
    return Tooltip(
      message: count == null
          ? 'Checking active games'
          : '$count active games and lobbies',
      child: Semantics(
        excludeSemantics: true,
        label: count == null
            ? 'Active game count unavailable'
            : '$count active games and lobbies',
        child: count != null && count > 0
            ? Badge(label: Text(label))
            : Text(label, style: Theme.of(context).textTheme.labelSmall),
      ),
    );
  }
}
