import 'package:bonfire/features/experiences/controllers/turns.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Widget withExperienceTurns(Widget? child) => Stack(
  children: [
    if (child != null) Positioned.fill(child: child),
    const Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(child: ExperienceTurnBanner()),
    ),
  ],
);

/// In-app notifications work on every platform and remain inside the PIN gate.
/// Background accounts stay isolated by the same connection key as game state.
class ExperienceTurnBanner extends ConsumerWidget {
  const ExperienceTurnBanner({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connections = ref.watch(connectionsControllerProvider);
    final turns = ref
        .watch(experienceTurnsProvider)
        .entries
        .where((e) => connections.connectionFor(e.key.serverKey) != null)
        .toList();
    if (turns.isEmpty) return const SizedBox.shrink();
    final turn = turns.first;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Material(
          elevation: 4,
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: ListTile(
            leading: const Icon(Icons.sports_esports_outlined),
            title: Text('Your turn in ${turn.value.gameId}'),
            subtitle: const Text(
              'Open this space’s Arcade to resume the game.',
            ),
            trailing: IconButton(
              tooltip: 'Dismiss turn notification',
              icon: const Icon(Icons.close),
              onPressed: () =>
                  ref.read(experienceTurnsProvider.notifier).dismiss(turn.key),
            ),
          ),
        ),
      ),
    );
  }
}
