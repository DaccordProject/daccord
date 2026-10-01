import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/experiences/views/experience_platform.dart';
import 'package:bonfire/features/experiences/views/experience_session_view.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Re-exported so the spaces feature's existing `arcade.dart` import keeps
// resolving the sidebar entry.
export 'package:bonfire/features/experiences/views/space_arcade_entry.dart'
    show SpaceArcadeEntry;

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
  const SpaceArcade({
    super.key,
    required this.serverKey,
    required this.spaceId,
    this.manage = false,
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
  }

  @override
  void dispose() {
    _generation++;
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
      await _refresh();
    } catch (e) {
      if (_valid) setState(() => _error = _errorText(e));
    } finally {
      if (_valid) setState(() => _busy = false);
    }
  }

  Future<void> _create(AccordExperienceManifest manifest) async {
    final choice = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Create ${manifest.name} lobby'),
        content: const Text(
          'An open lobby is visible to members. An invite-only lobby uses member IDs you choose.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Open'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Invite-only'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted || !_valid) return;
    var invited = <String>[];
    if (choice) {
      final controller = TextEditingController();
      final text = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Invite members'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Member IDs, separated by commas',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Create'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (text == null || !_valid) return;
      invited = text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    setState(() => _busy = true);
    try {
      final session =
          _require(
                await _client!.experiences.create(
                  widget.spaceId,
                  manifest.id,
                  inviteOnly: choice,
                  invited: invited,
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
            Text(manifest.name, style: Theme.of(context).textTheme.titleMedium),
            Text(manifest.description),
            if (!available) const Text('Unavailable on this platform.'),
            Text(
              '${manifest.publisher} · ${manifest.version} · ${manifest.minPlayers}–${manifest.maxPlayers} players · ${manifest.sessionMode == 'turn_based' ? 'Turn-based' : 'Real-time'}',
            ),
            Wrap(
              spacing: 8,
              children: [
                if (enabled && available && _arcade?['enabled'] == true)
                  FilledButton(
                    onPressed: _busy ? null : () => _create(manifest),
                    child: const Text('Create lobby'),
                  ),
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
    final displayed = widget.manage
        ? games
        : games.where((g) => g['enabled'] == true).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.manage ? 'Game directory & Arcade' : 'Space Arcade'),
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
            padding: const EdgeInsets.all(16),
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_arcade == null && _error == null)
                const Center(child: CircularProgressIndicator()),
              if (widget.manage && _arcade != null)
                SwitchListTile(
                  title: const Text('Space Arcade'),
                  subtitle: const Text(
                    'Allow members to create and join game sessions',
                  ),
                  value: _arcade!['enabled'] == true,
                  onChanged: _busy
                      ? null
                      : (enabled) => _mutate(
                          () => _client!.experiences.configureArcade(
                            widget.spaceId,
                            enabled: enabled,
                          ),
                        ),
                ),
              if (displayed.isEmpty && _arcade != null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No experiences enabled in this space.'),
                ),
              for (final game in displayed) _game(game),
              if (_sessions.isNotEmpty)
                Text(
                  'Lobbies & ongoing games',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              for (final session in _sessions.where((s) => s.state != 'ended'))
                ListTile(
                  leading: Icon(
                    session.turnUserId == _user
                        ? Icons.notifications_active_outlined
                        : Icons.sports_esports_outlined,
                  ),
                  title: Text(session.gameId),
                  subtitle: Text(
                    '${session.state} · ${session.participants.where((p) => p['role'] == 'player').length}/2 players${session.turnUserId == _user ? ' · Your turn' : ''}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(session),
                ),
              if (widget.manage && _directory.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'Reviewed releases',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                for (final game in _directory)
                  Card(
                    child: ListTile(
                      title: Text('${game.name} ${game.version}'),
                      subtitle: Text(
                        '${game.publisher}\n${game.description}\n${game.platforms.join(', ')} · Host API ${game.hostApi}\n${game.capabilities.join(', ')}',
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
                        child: const Text('Enable version'),
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
