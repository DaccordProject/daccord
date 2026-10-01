import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:experience_runtime/experience_runtime.dart';
import 'package:bonfire/features/experiences/services/experience_package.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'experience_canvas.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

String experiencePlatform(BuildContext context) => kIsWeb
    ? 'web'
    : switch (Theme.of(context).platform) {
        TargetPlatform.linux => 'linux',
        TargetPlatform.windows => 'windows',
        TargetPlatform.macOS => 'macos',
        TargetPlatform.android => 'android',
        TargetPlatform.iOS => 'ios',
        _ => 'unsupported',
      };

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

  Object? _require(RestResult result) {
    if (!result.ok) {
      throw StateError(
        result.error?.message ?? 'The Arcade is unavailable on this server.',
      );
    }
    return result.data;
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
        setState(() => _error = e.toString().replaceFirst('Bad state: ', ''));
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
      if (_valid)
        setState(() => _error = e.toString().replaceFirst('Bad state: ', ''));
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
      if (_valid) setState(() => _error = e.toString());
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

class ExperienceSessionView extends ConsumerStatefulWidget {
  final String serverKey;
  final String spaceId;
  final AccordExperienceSession initialSession;
  const ExperienceSessionView({
    super.key,
    required this.serverKey,
    required this.spaceId,
    required this.initialSession,
  });
  @override
  ConsumerState<ExperienceSessionView> createState() =>
      _ExperienceSessionViewState();
}

class _ExperienceSessionViewState extends ConsumerState<ExperienceSessionView>
    with WidgetsBindingObserver {
  late AccordExperienceSession _session;
  AccordClient? _client;
  ModalRoute<dynamic>? _route;
  ExperienceModule? _module;
  List<ExperienceDrawing> _drawings = [];
  StreamSubscription<Map<String, dynamic>>? _events;
  Timer? _timer;
  Timer? _inputTimer;
  ExperienceLiveSession? _live;
  StreamSubscription<AccordExperienceSession>? _liveEvents;
  int? _pendingInput;
  bool _connecting = false;
  bool _busy = false;
  bool _foreground = true;
  String? _error;
  int _generation = 0;
  int? _selected;
  String get _user =>
      ref
          .read(connectionsControllerProvider)
          .connectionFor(widget.serverKey)
          ?.session
          .userId ??
      '';
  bool get _valid =>
      mounted &&
      _foreground &&
      _route?.isCurrent == true &&
      _client != null &&
      ref.read(accordAuthProvider.notifier).clientForKey(widget.serverKey) ==
          _client &&
      ref.readActiveServerKey() == widget.serverKey;
  Map<String, dynamic>? get _participant {
    for (final p in _session.participants) {
      if (p['user_id'] == _user) return p;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _session = widget.initialSession;
    WidgetsBinding.instance.addObserver(this);
    _client = ref
        .read(accordAuthProvider.notifier)
        .clientForKey(widget.serverKey);
    _events = _client?.onExperienceSession.listen((data) {
      if (_valid &&
          data['id'] == _session.id &&
          data['space_id'] == widget.spaceId) {
        try {
          _accept(AccordExperienceSession.fromJson(data));
        } catch (_) {
          _invalidate('Invalid game snapshot');
        }
      }
    });
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_approved) _invalidate('Checking release approval…');
      unawaited(_refresh());
    });
    unawaited(_refresh());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    if (_route?.isCurrent == true) {
      unawaited(_refresh());
    } else {
      _generation++;
      _invalidate(null);
    }
  }

  DateTime? _approvalExpires;
  bool get _approved =>
      _valid &&
      _approvalExpires != null &&
      DateTime.now().isBefore(_approvalExpires!);

  void _invalidate(String? error) {
    _module = null;
    _approvalExpires = null;
    _drawings = [];
    _closeLive();
    if (mounted) setState(() => _error = error);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _generation++;
    _invalidate(null);
    if (_foreground) unawaited(_refresh());
  }

  @override
  void dispose() {
    _generation++;
    _module = null;
    _timer?.cancel();
    _closeLive();
    _events?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _accept(AccordExperienceSession session) {
    if (!_valid ||
        session.id != _session.id ||
        session.spaceId != widget.spaceId ||
        session.revision < _session.revision)
      return;
    final identityChanged =
        session.digest != _session.digest ||
        session.version != _session.version ||
        session.gameId != _session.gameId;
    setState(() {
      _session = session;
      if (session.state == 'ended' || identityChanged) {
        _generation++;
        _module = null;
        _approvalExpires = null;
        _drawings = [];
        _closeLive();
      } else {
        _render();
      }
    });
  }

  Object? _require(RestResult result) {
    if (!result.ok) {
      throw StateError(result.error?.message ?? 'Experience unavailable');
    }
    return result.data;
  }

  bool _refreshing = false;
  Future<void> _refresh() async {
    if (!_valid || _refreshing) return;
    _refreshing = true;
    final generation = ++_generation;
    final requestedAt = DateTime.now();
    try {
      final session =
          _require(
                await _client!.experiences.session(widget.spaceId, _session.id),
              )
              as AccordExperienceSession;
      if (!_valid || generation != _generation) return;
      ExperienceModule? module;
      if (session.state == 'running') {
        final release =
            _require(
                  await _client!.experiences.package(
                    widget.spaceId,
                    session.gameId,
                  ),
                )
                as Map;
        if (!_valid || generation != _generation) return;
        module = await validateExperiencePackage(
          release,
          digest: session.digest,
          gameId: session.gameId,
          version: session.version,
          platform: _platform(),
        );
      }
      if (!_valid || generation != _generation) return;
      setState(() {
        if (session.revision >= _session.revision) _session = session;
        _module = module;
        // The lease includes request time. A slow or stale refresh cannot
        // extend execution beyond the five-second approval window.
        _approvalExpires = requestedAt.add(const Duration(seconds: 5));
        _error = null;
        _render();
      });
      if (_approved &&
          _module != null &&
          _session.mode == 'real_time' &&
          _session.state == 'running' &&
          _participant != null) {
        unawaited(_connectLive());
      }
    } catch (e) {
      if (_valid && generation == _generation)
        _invalidate(e.toString().replaceFirst('Bad state: ', ''));
    } finally {
      _refreshing = false;
    }
  }

  void _closeLive() {
    _inputTimer?.cancel();
    _inputTimer = null;
    _pendingInput = null;
    unawaited(_liveEvents?.cancel());
    _liveEvents = null;
    unawaited(_live?.close());
    _live = null;
  }

  Future<void> _connectLive() async {
    if (_live != null || _connecting || !_approved) return;
    _connecting = true;
    final generation = _generation;
    try {
      final live = await ExperienceLiveSession.connect(
        _client!,
        widget.spaceId,
        _session.id,
      );
      if (!_approved ||
          generation != _generation ||
          _session.state != 'running') {
        await live.close();
        return;
      }
      _live = live;
      _liveEvents = live.snapshots.listen(
        (session) {
          if (_approved) _accept(session);
        },
        onError: (Object e) {
          _closeLive();
          if (_valid)
            setState(() => _error = 'Live connection lost. Reconnecting…');
        },
        onDone: _closeLive,
      );
      _inputTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        final value = _pendingInput;
        _pendingInput = null;
        if (value == null ||
            !_approved ||
            _module == null ||
            _participant?['role'] != 'player')
          return;
        try {
          final output = _module!.invoke(
            'input',
            [1, value, 0],
            readState: _read,
            grantValid: () => _approved && _session.state == 'running',
          );
          if (output.actions.isNotEmpty) _live?.input(output.actions.single.a);
        } catch (e) {
          _invalidate('Experience stopped: $e');
        }
      });
    } catch (_) {
      if (_valid)
        setState(() => _error = 'Live connection unavailable. Reconnecting…');
    } finally {
      _connecting = false;
    }
  }

  String _platform() => experiencePlatform(context);
  int _read(int key, int index) {
    final values = _session.game[key == 0 ? 'board' : 'rects'];
    if (values is! List || index >= values.length) return 0;
    return values[index] as int;
  }

  void _render() {
    if (_module == null || !_approved || _session.state != 'running') {
      _drawings = [];
      return;
    }
    final generation = _generation;
    try {
      _drawings = _module!
          .invoke(
            'render',
            [],
            readState: _read,
            grantValid: () => _approved && generation == _generation,
          )
          .drawings;
    } catch (e) {
      _module = null;
      _drawings = [];
      _approvalExpires = null;
      _error = 'Experience stopped: $e';
      _closeLive();
    }
  }

  Future<void> _membership(
    String operation, {
    bool spectator = false,
    bool ready = false,
  }) => _mutate(
    () => _client!.experiences.membership(
      widget.spaceId,
      _session.id,
      operation,
      _session.revision,
      spectator: spectator,
      ready: ready,
    ),
  );
  Future<void> _mutate(Future<RestResult> Function() request) async {
    if (_busy || !_valid) return;
    setState(() => _busy = true);
    try {
      final result = _require(await request()) as AccordExperienceSession;
      if (_valid) _accept(result);
    } catch (e) {
      if (_valid) {
        setState(() => _error = e.toString().replaceFirst('Bad state: ', ''));
        await _refresh();
      }
    } finally {
      if (_valid) setState(() => _busy = false);
    }
  }

  Future<void> _cell(int cell) async {
    if (_busy ||
        !_approved ||
        _module == null ||
        _participant?['role'] != 'player' ||
        _session.turnUserId != _user) {
      return;
    }
    if (_selected == null) {
      setState(() => _selected = cell);
      return;
    }
    final from = _selected!;
    setState(() => _selected = null);
    final output = _module!.invoke(
      'input',
      [0, from, cell],
      readState: _read,
      grantValid: () => _approved,
    );
    if (output.actions.isEmpty) return;
    final action = output.actions.single;
    String? promotion;
    final piece = (_session.game['board'] as List)[from];
    if ((piece == 1 && cell >= 56) || (piece == 7 && cell < 8)) {
      promotion = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Promote pawn'),
          children: [
            for (final entry in [
              ('q', 'Queen'),
              ('r', 'Rook'),
              ('b', 'Bishop'),
              ('n', 'Knight'),
            ])
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, entry.$1),
                child: Text(entry.$2),
              ),
          ],
        ),
      );
      if (promotion == null || !_valid) return;
    }
    await _mutate(
      () => _client!.experiences.action(
        widget.spaceId,
        _session.id,
        _session.revision,
        'move',
        a: action.a,
        b: action.b,
        promotion: promotion,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(accordAuthProvider);
    ref.watch(connectionsControllerProvider);
    if (!_valid) {
      _module = null;
      _approvalExpires = null;
      _drawings = [];
      _closeLive();
      return const Scaffold(
        body: Center(
          child: Text('This experience is no longer active on this account.'),
        ),
      );
    }
    final participant = _participant;
    return Scaffold(
      appBar: AppBar(
        title: Text('${_session.gameId} · ${_session.state}'),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_session.result != null)
                Text(
                  '${_session.result!['outcome'] == 'win'
                      ? (_session.result!['winner_user_id'] == _user ? 'You won' : 'Winner: ${_session.result!['winner_user_id']}')
                      : _session.result!['outcome'] == 'draw'
                      ? 'Draw'
                      : 'Cancelled'} · ${_session.result!['reason']}',
                ),
              if (_session.turnUserId != null)
                Text(
                  _session.turnUserId == _user
                      ? 'Your turn'
                      : 'Waiting for the other player',
                ),
              for (final p in _session.participants)
                ListTile(
                  title: Text(p['user_id'] as String),
                  subtitle: Text(
                    '${p['role']}${p['slot'] == null ? '' : ' · Slot ${(p['slot'] as int) + 1}'}',
                  ),
                  trailing: p['ready'] == true ? const Icon(Icons.check) : null,
                ),
              if (_session.state != 'ended')
                Wrap(
                  spacing: 8,
                  children: [
                    if (participant == null) ...[
                      if (_session.state == 'lobby')
                        FilledButton(
                          onPressed: _busy ? null : () => _membership('join'),
                          child: const Text('Join as player'),
                        ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _membership('join', spectator: true),
                        child: const Text('Spectate'),
                      ),
                    ],
                    if (participant?['role'] == 'player' &&
                        _session.state == 'lobby')
                      FilledButton(
                        onPressed: _busy
                            ? null
                            : () => _membership(
                                'ready',
                                ready: participant!['ready'] != true,
                              ),
                        child: Text(
                          participant?['ready'] == true ? 'Not ready' : 'Ready',
                        ),
                      ),
                    if (_session.hostUserId == _user &&
                        _session.state == 'lobby')
                      FilledButton(
                        onPressed: _busy ? null : () => _membership('start'),
                        child: const Text('Start'),
                      ),
                    if (participant != null)
                      TextButton(
                        onPressed: _busy ? null : () => _membership('leave'),
                        child: const Text('Leave session'),
                      ),
                    if (participant?['role'] == 'player' &&
                        _session.state == 'running')
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _mutate(
                                () => _client!.experiences.action(
                                  widget.spaceId,
                                  _session.id,
                                  _session.revision,
                                  'resign',
                                ),
                              ),
                        child: const Text('Resign'),
                      ),
                  ],
                ),
              if (_session.mode == 'real_time' &&
                  _session.state == 'running') ...[
                Text('Score: ${_session.game['score'] ?? [0, 0]}'),
                if (_session.game['paused'] == true)
                  const Text('Paused while the other player reconnects.'),
              ],
              if (_drawings.isNotEmpty)
                ExperienceCanvas(
                  drawings: _drawings,
                  selected: _selected,
                  onCell:
                      _session.mode == 'turn_based' &&
                          _participant?['role'] == 'player' &&
                          _session.turnUserId == _user &&
                          _approved
                      ? (cell) => unawaited(_cell(cell))
                      : null,
                ),
              if (_session.mode == 'real_time' &&
                  participant?['role'] == 'player' &&
                  _session.state == 'running')
                Slider(
                  value:
                      ((_session.game['rects']
                                  as List)[(participant!['slot'] as int) * 4 +
                                  1]
                              as int)
                          .toDouble(),
                  min: 0,
                  max: 864,
                  onChanged: _live == null
                      ? null
                      : (value) => _pendingInput = value.round(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
