import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/experiences/views/arcade_game_artwork.dart';
import 'package:bonfire/features/experiences/views/arcade_identity.dart';
import 'package:bonfire/features/experiences/views/experience_idle_countdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ArcadeLobbyTile extends ConsumerWidget {
  const ArcadeLobbyTile({
    super.key,
    required this.serverKey,
    required this.spaceId,
    required this.session,
    required this.onTap,
    this.manifest,
    this.currentUserId,
  });
  final String serverKey;
  final String spaceId;
  final AccordExperienceSession session;
  final AccordExperienceManifest? manifest;
  final String? currentUserId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final accent = arcadeGameColor(session.gameId);
    final host = watchArcadeIdentity(
      ref,
      serverKey: serverKey,
      spaceId: spaceId,
      userId: session.hostUserId,
    );
    final players = session.participants
        .where((p) => p['role'] == 'player')
        .toList();
    final capacity = manifest?.maxPlayers;
    final running = session.state == 'running';
    final private = session.json['invite_only'] == true;
    final name = manifest?.name ?? arcadeGameName(session.gameId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: accent.withValues(alpha: .2)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 72,
                  height: 72,
                  child: ArcadeGameArtwork(gameId: session.gameId, radius: 12),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          Text(
                            running
                                ? 'IN PROGRESS'
                                : private
                                ? 'INVITE ONLY'
                                : 'OPEN LOBBY',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: accent,
                              letterSpacing: 1.1,
                            ),
                          ),
                          if (session.turnUserId == currentUserId)
                            Text(
                              'Your turn',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${host.name}’s $name',
                        style: theme.textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (final player in players)
                            _PlayerChip(
                              serverKey: serverKey,
                              spaceId: spaceId,
                              userId: player['user_id'] as String,
                            ),
                          if (!running &&
                              capacity != null &&
                              players.length < capacity)
                            Text(
                              'Waiting for ${capacity - players.length == 1 ? 'a player' : '${capacity - players.length} players'}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            Icons.people_outline,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '${players.length}${capacity == null ? '' : '/$capacity'} players',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ExperienceIdleCountdown(session: session),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerChip extends ConsumerWidget {
  const _PlayerChip({
    required this.serverKey,
    required this.spaceId,
    required this.userId,
  });
  final String serverKey;
  final String spaceId;
  final String userId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = watchArcadeIdentity(
      ref,
      serverKey: serverKey,
      spaceId: spaceId,
      userId: userId,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ArcadePlayerAvatar(identity: identity, radius: 12),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            identity.name,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
