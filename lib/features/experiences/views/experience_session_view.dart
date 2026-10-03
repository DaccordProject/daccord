import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/experiences/services/experience_package.dart';
import 'package:bonfire/features/experiences/views/experience_canvas.dart';
import 'package:bonfire/features/experiences/views/experience_platform.dart';
import 'package:bonfire/features/experiences/views/experience_idle_countdown.dart';
import 'package:bonfire/features/experiences/views/arcade_game_artwork.dart';
import 'package:bonfire/features/experiences/views/arcade_identity.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:experience_runtime/experience_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Object? _require(RestResult result) {
  if (!result.ok) {
    throw StateError(result.errorMessageOr('Experience unavailable'));
  }
  return result.data;
}

class _ArcadeParticipant extends ConsumerWidget {
  const _ArcadeParticipant({
    required this.serverKey,
    required this.spaceId,
    required this.participant,
    required this.hostUserId,
  });
  final String serverKey;
  final String spaceId;
  final Map<String, dynamic> participant;
  final String hostUserId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = participant['user_id'] as String;
    final identity = watchArcadeIdentity(
      ref,
      serverKey: serverKey,
      spaceId: spaceId,
      userId: userId,
    );
    final player = participant['role'] == 'player';
    return ListTile(
      leading: ArcadePlayerAvatar(identity: identity, radius: 18),
      title: Text(identity.name),
      subtitle: Text(
        '${player ? 'Player' : 'Spectator'}${userId == hostUserId ? ' · Host' : ''}${participant['slot'] == null ? '' : ' · Seat ${(participant['slot'] as int) + 1}'}',
      ),
      trailing: participant['ready'] == true
          ? const Tooltip(
              message: 'Ready',
              child: Icon(Icons.check_circle_outline),
            )
          : null,
    );
  }
}

String _errorText(Object e) => e is StateError ? e.message : '$e';

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
      if (_session.state == 'ended') return;
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
        session.revision < _session.revision) {
      return;
    }
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

  bool _refreshing = false;
  Future<void> _refresh() async {
    if (!_valid || _refreshing || _session.state == 'ended') return;
    _refreshing = true;
    final generation = ++_generation;
    final requestedAt = DateTime.now();
    final platform = experiencePlatform(context);
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
          platform: platform,
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
      if (_valid && generation == _generation) _invalidate(_errorText(e));
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
          if (_valid) {
            setState(() => _error = 'Live connection lost. Reconnecting…');
          }
        },
        onDone: _closeLive,
      );
      _inputTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        final value = _pendingInput;
        _pendingInput = null;
        if (value == null ||
            !_approved ||
            _module == null ||
            _participant?['role'] != 'player') {
          return;
        }
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
      if (_valid) {
        setState(() => _error = 'Live connection unavailable. Reconnecting…');
      }
    } finally {
      _connecting = false;
    }
  }

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
        setState(() => _error = _errorText(e));
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
    final winnerId = _session.result?['winner_user_id'] as String?;
    final winner = winnerId == null
        ? null
        : watchArcadeIdentity(
            ref,
            serverKey: widget.serverKey,
            spaceId: widget.spaceId,
            userId: winnerId,
          );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${arcadeGameName(_session.gameId)} · ${_session.state == 'lobby'
              ? 'Lobby'
              : _session.state == 'running'
              ? 'Playing'
              : 'Finished'}',
        ),
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
                  _session.result!['reason'] == 'idle_timeout'
                      ? 'Game removed after seven days without player activity.'
                      : '${_session.result!['outcome'] == 'win'
                            ? (winnerId == _user ? 'You won' : 'Winner: ${winner?.name ?? 'Player'}')
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
              ExperienceIdleCountdown(session: _session),
              for (final p in _session.participants)
                _ArcadeParticipant(
                  serverKey: widget.serverKey,
                  spaceId: widget.spaceId,
                  participant: p,
                  hostUserId: _session.hostUserId,
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
