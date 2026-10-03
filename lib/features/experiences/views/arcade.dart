import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/experiences/views/experience_platform.dart';
import 'package:bonfire/features/experiences/views/arcade_game_artwork.dart';
import 'package:bonfire/features/experiences/views/arcade_game_picker.dart';
import 'package:bonfire/features/experiences/views/arcade_lobby_setup.dart';
import 'package:bonfire/features/experiences/views/arcade_lobby_tile.dart';
import 'package:bonfire/features/experiences/views/arcade_activity_badge.dart';
import 'package:bonfire/features/experiences/views/experience_session_view.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Object? _require(RestResult result) {
  if (!result.ok) {
    throw StateError(
      result.errorMessageOr('The Arcade is unavailable on this server.'),
    );
  }
  return result.data;
}

String _errorText(Object e) => e is StateError ? e.message : '$e';

Future<void> showSpaceArcade(
  BuildContext context, {
  required String serverKey,
  required String spaceId,
  bool manage = false,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) =>
        SpaceArcade(serverKey: serverKey, spaceId: spaceId, manage: manage),
  ),
);

class SpaceArcade extends ConsumerStatefulWidget {
  final String serverKey;
  final String spaceId;
  final bool manage;
  final String? channelName;
  final bool embedded;
  const SpaceArcade({
    super.key,
    required this.serverKey,
    required this.spaceId,
    this.manage = false,
    this.channelName,
    this.embedded = false,
  });
  @override
  ConsumerState<SpaceArcade> createState() => _SpaceArcadeState();
}

class _SpaceArcadeState extends ConsumerState<SpaceArcade> {
  AccordClient? _client;
  StreamSubscription<Map<String, dynamic>>? _events;
  Map<String, dynamic>? _arcade;
  List<AccordExperienceSession> _sessions = [];
  List<AccordExperienceManifest> _directory = [];
  bool _busy = false;
  String? _error;
  int _generation = 0;
  Timer? _timer;
  bool get _valid =>
      mounted &&
      _client != null &&
      ref.read(accordAuthProvider.notifier).clientForKey(widget.serverKey) ==
          _client &&
      ref.readActiveServerKey() == widget.serverKey;
  String? get _user => ref
      .read(connectionsControllerProvider)
      .connectionFor(widget.serverKey)
      ?.session
      .userId;

  @override
  void initState() {
    super.initState();
    _client = ref
        .read(accordAuthProvider.notifier)
        .clientForKey(widget.serverKey);
    _events = _client?.onExperienceSession.listen((data) {
      if (data['space_id'] == widget.spaceId && _valid) unawaited(_refresh());
    });
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_valid && !_busy && ModalRoute.of(context)?.isCurrent != false) {
        unawaited(_refresh());
      }
    });
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    _events?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!_valid) return;
    final generation = ++_generation;
    try {
      final results = await Future.wait([
        _client!.experiences.arcade(widget.spaceId),
        _client!.experiences.sessions(widget.spaceId),
        if (widget.manage) _client!.experiences.directory(widget.spaceId),
      ]);
      final arcade = Map<String, dynamic>.from(_require(results[0]) as Map);
      final sessions = (_require(results[1]) as List)
          .cast<AccordExperienceSession>();
      final directory = widget.manage
          ? (_require(results[2]) as List).cast<AccordExperienceManifest>()
          : <AccordExperienceManifest>[];
      if (!_valid || generation != _generation) return;
      setState(() {
        _arcade = arcade;
        _sessions = sessions;
        _directory = directory;
        _error = null;
      });
    } catch (e) {
      if (_valid && generation == _generation) {
        setState(() => _error = _errorText(e));
      }
    }
  }

  Future<void> _mutate(Future<RestResult> Function() request) async {
    if (_busy || !_valid) return;
    setState(() => _busy = true);
    try {
      _require(await request());
      ref.invalidate(
        arcadeActivityProvider((
          serverKey: widget.serverKey,
          spaceId: widget.spaceId,
        )),
      );
      await _refresh();
    } catch (e) {
      if (_valid) setState(() => _error = _errorText(e));
    } finally {
      if (_valid) setState(() => _busy = false);
    }
  }

  Future<void> _chooseGame(List<AccordExperienceManifest> games) async {
    final game = await showDialog<AccordExperienceManifest>(
      context: context,
      builder: (_) => ArcadeGamePicker(games: games),
    );
    if (game != null && _valid && !_busy) await _create(game);
  }

  Future<void> _create(AccordExperienceManifest manifest) async {
    final choice = await showDialog<ArcadeLobbyChoice>(
      context: context,
      builder: (_) => ArcadeLobbySetup(
        client: _client!,
        spaceId: widget.spaceId,
        currentUserId: _user,
        game: manifest,
      ),
    );
    if (choice == null || !mounted || !_valid) return;
    setState(() => _busy = true);
    try {
      final session =
          _require(
                await _client!.experiences.create(
                  widget.spaceId,
                  manifest.id,
                  inviteOnly: choice.inviteOnly,
                  invited: choice.invited,
                ),
              )
              as AccordExperienceSession;
      if (_valid) await _open(session);
    } catch (e) {
      if (_valid) setState(() => _error = _errorText(e));
    } finally {
      if (_valid) {
        setState(() => _busy = false);
        await _refresh();
      }
    }
  }

  Future<void> _open(AccordExperienceSession session) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ExperienceSessionView(
          serverKey: widget.serverKey,
          spaceId: widget.spaceId,
          initialSession: session,
        ),
      ),
    );
    if (_valid) await _refresh();
  }

  Widget _game(Map game) {
    final manifest = AccordExperienceManifest.fromJson(
      Map<String, dynamic>.from(game['manifest'] as Map),
    );
    final enabled = game['enabled'] == true;
    final available = manifest.platforms.contains(experiencePlatform(context));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 48,
                  height: 48,
                  child: ArcadeGameArtwork(gameId: manifest.id, radius: 10),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        manifest.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(manifest.description),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!available) const Text('Unavailable on this platform.'),
            Text(
              '${manifest.publisher} · ${manifest.version} · ${manifest.minPlayers}–${manifest.maxPlayers} players · ${manifest.sessionMode == 'turn_based' ? 'Turn-based' : 'Real-time'}',
            ),
            Wrap(
              spacing: 8,
              children: [
                if (widget.manage) ...[
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _mutate(
                            () => _client!.experiences.enable(
                              widget.spaceId,
                              manifest.id,
                              manifest.version,
                            ),
                          ),
                    child: Text(
                      enabled ? 'Re-enable pinned version' : 'Enable',
                    ),
                  ),
                  if (enabled)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _mutate(
                              () => _client!.experiences.configure(
                                widget.spaceId,
                                manifest.id,
                                enabled: false,
                              ),
                            ),
                      child: const Text('Disable'),
                    ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _mutate(
                            () => _client!.experiences.remove(
                              widget.spaceId,
                              manifest.id,
                            ),
                          ),
                    child: const Text('Remove'),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            final controller = TextEditingController(
                              text:
                                  '${(game['config'] as Map?)?['turn_timeout_seconds'] ?? 0}',
                            );
                            final timeout = await showDialog<int>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Turn timeout'),
                                content: TextField(
                                  controller: controller,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Seconds (0 means no timeout)',
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(
                                      context,
                                      int.tryParse(controller.text),
                                    ),
                                    child: const Text('Save'),
                                  ),
                                ],
                              ),
                            );
                            controller.dispose();
                            if (timeout != null && _valid) {
                              await _mutate(
                                () => _client!.experiences.configure(
                                  widget.spaceId,
                                  manifest.id,
                                  enabled: enabled,
                                  turnTimeoutSeconds: timeout,
                                ),
                              );
                            }
                          },
                    child: const Text('Configure'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(accordAuthProvider);
    ref.watch(connectionsControllerProvider);
    if (!_valid) {
      return const Scaffold(
        body: Center(child: Text('This account is no longer connected.')),
      );
    }
    final games = (_arcade?['experiences'] as List? ?? []).cast<Map>();
    final manifests = {
      for (final game in games)
        (game['manifest'] as Map)['id']
            as String: AccordExperienceManifest.fromJson(
          Map<String, dynamic>.from(game['manifest'] as Map),
        ),
    };
    final playable = [
      for (final game in games)
        if (game['enabled'] == true &&
            manifests[(game['manifest'] as Map)['id']]!.platforms.contains(
              experiencePlatform(context),
            ))
          manifests[(game['manifest'] as Map)['id']]!,
    ];
    final sessions = _sessions.where((s) => s.isActive).toList();
    final enabled = _arcade?['enabled'] == true;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        title: Text(
          widget.channelName == null ||
                  widget.channelName!.toLowerCase() == 'arcade'
              ? 'Arcade'
              : widget.channelName!,
        ),
        actions: [
          IconButton(
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              if (_arcade == null && _error == null)
                const Center(child: CircularProgressIndicator()),
              if (_arcade != null) ...[
                Row(
                  children: [
                    Text('Lobbies', style: theme.textTheme.titleLarge),
                    const SizedBox(width: 10),
                    Text(
                      '${sessions.length}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (sessions.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.sports_esports_outlined,
                          size: 40,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          !enabled
                              ? 'Arcade is currently closed'
                              : playable.isEmpty
                              ? 'No games available yet'
                              : 'Be the first to play',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          !enabled
                              ? 'A community manager can reopen it in Arcade settings.'
                              : playable.isEmpty
                              ? 'A community manager can add games in Arcade settings.'
                              : 'Create a lobby and your friends will find it here.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                for (final session in sessions)
                  ArcadeLobbyTile(
                    serverKey: widget.serverKey,
                    spaceId: widget.spaceId,
                    session: session,
                    manifest: manifests[session.gameId],
                    currentUserId: _user,
                    onTap: () => _open(session),
                  ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: LinearGradient(
                      colors: [
                        theme.colorScheme.primary.withValues(alpha: .15),
                        const Color(0xff55e6da).withValues(alpha: .04),
                      ],
                    ),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: .18),
                    ),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) => Wrap(
                      spacing: 24,
                      runSpacing: 20,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      alignment: WrapAlignment.spaceBetween,
                      children: [
                        SizedBox(
                          width: constraints.maxWidth >= 600
                              ? constraints.maxWidth - 200
                              : constraints.maxWidth,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Start a game',
                                style: theme.textTheme.titleLarge,
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Pick a game and invite your friends.',
                              ),
                            ],
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: _busy || !enabled || playable.isEmpty
                              ? null
                              : () => _chooseGame(playable),
                          icon: const Icon(Icons.add),
                          label: const Text('Create lobby'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),
              ],
              if (widget.manage && _arcade != null) ...[
                const SizedBox(height: 32),
                Text('Arcade settings', style: theme.textTheme.titleLarge),
                SwitchListTile(
                  title: const Text('Arcade'),
                  subtitle: const Text(
                    'Allow members to create and join game sessions',
                  ),
                  value: enabled,
                  onChanged: _busy
                      ? null
                      : (enabled) => _mutate(
                          () => _client!.experiences.configureArcade(
                            widget.spaceId,
                            enabled: enabled,
                          ),
                        ),
                ),
                const SizedBox(height: 16),
                Text('Installed games', style: theme.textTheme.titleMedium),
                for (final game in games) _game(game),
              ],
              if (widget.manage && _directory.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('Available games', style: theme.textTheme.titleLarge),
                for (final game in _directory)
                  Card(
                    child: ListTile(
                      leading: SizedBox(
                        width: 48,
                        height: 48,
                        child: ArcadeGameArtwork(gameId: game.id, radius: 10),
                      ),
                      title: Text(game.name),
                      subtitle: Text(
                        '${game.description}\n${game.publisher} · ${game.version}',
                      ),
                      isThreeLine: true,
                      trailing: TextButton(
                        onPressed: _busy
                            ? null
                            : () => _mutate(
                                () => _client!.experiences.enable(
                                  widget.spaceId,
                                  game.id,
                                  game.version,
                                ),
                              ),
                        child: const Text('Add game'),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
