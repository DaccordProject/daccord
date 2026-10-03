import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/experiences/views/arcade_game_artwork.dart';
import 'package:flutter/material.dart';

class ArcadeGamePicker extends StatefulWidget {
  const ArcadeGamePicker({super.key, required this.games});
  final List<AccordExperienceManifest> games;
  @override
  State<ArcadeGamePicker> createState() => _ArcadeGamePickerState();
}

class _ArcadeGamePickerState extends State<ArcadeGamePicker> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final games = widget.games
        .where(
          (g) => '${g.name} ${g.description}'.toLowerCase().contains(
            _query.toLowerCase(),
          ),
        )
        .toList();
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 740, maxHeight: 650),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Choose your game',
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text('Pick a game and bring your friends.'),
            ),
            if (widget.games.length > 4)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Find a game',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
            Flexible(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 500 ? 2 : 1;
                  final width =
                      (constraints.maxWidth - 48 - (columns - 1) * 16) /
                      columns;
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: games.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('No games match your search.'),
                          )
                        : Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            children: [
                              for (final game in games)
                                SizedBox(
                                  width: width,
                                  child: _GameCard(game: game),
                                ),
                            ],
                          ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.game});
  final AccordExperienceManifest game;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = arcadeGameColor(game.id);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: color.withValues(alpha: .25)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.pop(context, game),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1.9,
              child: ArcadeGameArtwork(gameId: game.id, radius: 0),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          game.name,
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      Icon(Icons.arrow_forward_rounded, color: color, size: 20),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    game.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Text(
                        '${game.minPlayers == game.maxPlayers ? game.maxPlayers : '${game.minPlayers}–${game.maxPlayers}'} players',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: color,
                        ),
                      ),
                      Text(
                        game.sessionMode == 'turn_based'
                            ? 'Turn-based'
                            : 'Real-time',
                        style: theme.textTheme.labelMedium,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
