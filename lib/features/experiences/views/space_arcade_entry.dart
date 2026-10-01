import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/experiences/views/arcade.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Outside the channel list: one entry for each space whose Arcade is enabled.
class SpaceArcadeEntry extends ConsumerStatefulWidget {
  final String serverKey;
  final String spaceId;
  const SpaceArcadeEntry({
    super.key,
    required this.serverKey,
    required this.spaceId,
  });
  @override
  ConsumerState<SpaceArcadeEntry> createState() => _SpaceArcadeEntryState();
}

class _SpaceArcadeEntryState extends ConsumerState<SpaceArcadeEntry> {
  bool _visible = false;
  int _waiting = 0;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _refresh());
  }

  @override
  void didUpdateWidget(SpaceArcadeEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.serverKey != widget.serverKey ||
        oldWidget.spaceId != widget.spaceId) {
      _visible = false;
      _waiting = 0;
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    final server = widget.serverKey, space = widget.spaceId;
    final client = ref.read(accordAuthProvider.notifier).clientForKey(server);
    if (client == null) return;
    final result = await client.experiences.arcade(space);
    if (!mounted ||
        server != widget.serverKey ||
        space != widget.spaceId ||
        ref.read(accordAuthProvider.notifier).clientForKey(server) != client) {
      return;
    }
    final visible =
        result.ok &&
        result.data is Map &&
        (result.data as Map)['visible'] == true;
    var waiting = 0;
    if (visible) {
      final sessions = await client.experiences.sessions(space);
      final user = ref
          .read(connectionsControllerProvider)
          .connectionFor(server)
          ?.session
          .userId;
      if (sessions.ok && sessions.data is List) {
        waiting = (sessions.data as List)
            .whereType<AccordExperienceSession>()
            .where((s) => s.state == 'running' && s.turnUserId == user)
            .length;
      }
    }
    if (mounted &&
        server == widget.serverKey &&
        space == widget.spaceId &&
        ref.read(accordAuthProvider.notifier).clientForKey(server) == client) {
      setState(() {
        _visible = visible;
        _waiting = waiting;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(accordAuthProvider);
    ref.watch(connectionsControllerProvider);
    if (!_visible ||
        ref.read(accordAuthProvider.notifier).clientForKey(widget.serverKey) ==
            null) {
      return const SizedBox.shrink();
    }
    return ListTile(
      dense: true,
      leading: const Icon(Icons.sports_esports_outlined),
      title: const Text('Space Arcade'),
      trailing: _waiting == 0 ? null : Badge(label: Text('$_waiting')),
      subtitle: _waiting == 0 ? null : const Text('Your turn'),
      onTap: () => showSpaceArcade(
        context,
        serverKey: widget.serverKey,
        spaceId: widget.spaceId,
      ),
    );
  }
}
