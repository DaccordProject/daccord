import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../core/accord_config.dart';
import '../models/accord_relationship.dart';
import '../models/call_signal.dart';
import '../models/channel.dart';
import '../models/interaction.dart';
import '../models/invite.dart';
import '../models/member.dart';
import '../models/message.dart';
import '../models/presence.dart';
import '../models/sound.dart';
import '../models/space.dart';
import '../models/user.dart';
import '../models/voice_server_update.dart';
import '../models/voice_state.dart';
import '../utils/json_utils.dart';
import 'gateway_connection.dart';
import 'gateway_events.dart';
import 'gateway_intents.dart';
import 'gateway_opcodes.dart';

/// Connection lifecycle state of the gateway socket.
enum GatewayState { disconnected, connecting, connected, resuming }

/// Manages a single gateway WebSocket connection: the IDENTIFY/RESUME
/// handshake, heartbeating, automatic reconnect with backoff, and dispatch of
/// inbound events to typed broadcast streams.
class GatewaySocket {
  String token;
  String tokenType;
  List<String> intents;

  final GatewayConnectionFactory _factory;
  final Future<void> Function(Duration) _sleep;
  final double Function() _random;
  final String _osName;
  final int maxReconnectAttempts;

  /// How long [ensureConnected] waits for a heartbeat ACK before declaring a
  /// nominally-connected socket dead and forcing a reconnect.
  final Duration probeTimeout;

  AccordConfig? _config;
  GatewayConnection? _conn;
  StreamSubscription<String>? _sub;
  Timer? _heartbeatTimer;

  GatewayState _state = GatewayState.disconnected;
  String _sessionId = '';
  int _sequence = 0;
  int _heartbeatIntervalMs = AccordConfig.heartbeatIntervalDefault;
  bool _heartbeatAckReceived = true;
  String _gatewayUrl = '';
  int _reconnectAttempts = 0;
  bool _reconnectCancelled = false;
  bool _resumePending = false;
  bool _probePending = false;

  GatewaySocket({
    GatewayConnectionFactory? connectionFactory,
    Future<void> Function(Duration)? sleep,
    double Function()? random,
    String osName = 'dart',
    this.maxReconnectAttempts = 10,
    this.probeTimeout = const Duration(seconds: 5),
    this.token = '',
    this.tokenType = 'Bot',
    List<String>? intents,
  })  : _factory = connectionFactory ?? WebSocketGatewayConnection.connect,
        _sleep = sleep ?? Future.delayed,
        _random = random ?? Random().nextDouble,
        _osName = osName,
        intents = intents ?? [];

  // ── Event streams ────────────────────────────────────────────────────────

  final _controllers = <StreamController<dynamic>>[];

  StreamController<T> _ctrl<T>() {
    final c = StreamController<T>.broadcast();
    _controllers.add(c);
    return c;
  }

  late final _connected = _ctrl<void>();
  late final _disconnected = _ctrl<DisconnectInfo>();
  late final _reconnecting = _ctrl<ReconnectInfo>();
  late final _readyReceived = _ctrl<Map<String, dynamic>>();
  late final _resumed = _ctrl<void>();

  late final _spaceCreate = _ctrl<AccordSpace>();
  late final _spaceUpdate = _ctrl<AccordSpace>();
  late final _spaceDelete = _ctrl<Map<String, dynamic>>();

  late final _channelCreate = _ctrl<AccordChannel>();
  late final _channelUpdate = _ctrl<AccordChannel>();
  late final _channelDelete = _ctrl<AccordChannel>();
  late final _channelReorder = _ctrl<Map<String, dynamic>>();
  late final _channelPinsUpdate = _ctrl<Map<String, dynamic>>();
  late final _channelMuteCreate = _ctrl<Map<String, dynamic>>();
  late final _channelMuteDelete = _ctrl<Map<String, dynamic>>();

  late final _memberJoin = _ctrl<AccordMember>();
  late final _memberLeave = _ctrl<Map<String, dynamic>>();
  late final _memberUpdate = _ctrl<AccordMember>();
  late final _memberChunk = _ctrl<Map<String, dynamic>>();

  late final _roleCreate = _ctrl<Map<String, dynamic>>();
  late final _roleUpdate = _ctrl<Map<String, dynamic>>();
  late final _roleDelete = _ctrl<Map<String, dynamic>>();

  late final _messageCreate = _ctrl<AccordMessage>();
  late final _messageUpdate = _ctrl<AccordMessage>();
  late final _messageDelete = _ctrl<Map<String, dynamic>>();
  late final _messageDeleteBulk = _ctrl<Map<String, dynamic>>();
  late final _readStateUpdate = _ctrl<Map<String, dynamic>>();

  late final _reactionAdd = _ctrl<Map<String, dynamic>>();
  late final _reactionRemove = _ctrl<Map<String, dynamic>>();
  late final _reactionClear = _ctrl<Map<String, dynamic>>();
  late final _reactionClearEmoji = _ctrl<Map<String, dynamic>>();

  late final _presenceUpdate = _ctrl<AccordPresence>();
  late final _typingStart = _ctrl<Map<String, dynamic>>();

  late final _userUpdate = _ctrl<AccordUser>();

  late final _voiceStateUpdate = _ctrl<AccordVoiceState>();
  late final _voiceServerUpdate = _ctrl<AccordVoiceServerUpdate>();
  late final _voiceSignal = _ctrl<Map<String, dynamic>>();

  late final _callRing = _ctrl<AccordCallSignal>();
  late final _callDecline = _ctrl<AccordCallSignal>();
  late final _callCancel = _ctrl<AccordCallSignal>();
  late final _callEnd = _ctrl<AccordCallSignal>();

  late final _banCreate = _ctrl<Map<String, dynamic>>();
  late final _banDelete = _ctrl<Map<String, dynamic>>();

  late final _reportCreate = _ctrl<Map<String, dynamic>>();

  late final _inviteCreate = _ctrl<AccordInvite>();
  late final _inviteDelete = _ctrl<Map<String, dynamic>>();

  late final _interactionCreate = _ctrl<AccordInteraction>();

  late final _pluginInstalled = _ctrl<Map<String, dynamic>>();
  late final _pluginUninstalled = _ctrl<Map<String, dynamic>>();
  late final _pluginEvent = _ctrl<Map<String, dynamic>>();
  late final _pluginSessionState = _ctrl<Map<String, dynamic>>();
  late final _pluginRoleChanged = _ctrl<Map<String, dynamic>>();
  late final _pluginLeaderboardUpdated = _ctrl<Map<String, dynamic>>();

  late final _emojiCreate = _ctrl<Map<String, dynamic>>();
  late final _emojiUpdate = _ctrl<Map<String, dynamic>>();
  late final _emojiDelete = _ctrl<Map<String, dynamic>>();

  late final _soundboardCreate = _ctrl<AccordSound>();
  late final _soundboardUpdate = _ctrl<AccordSound>();
  late final _soundboardDelete = _ctrl<Map<String, dynamic>>();
  late final _soundboardPlay = _ctrl<Map<String, dynamic>>();

  late final _relationshipAdd = _ctrl<AccordRelationship>();
  late final _relationshipUpdate = _ctrl<AccordRelationship>();
  late final _relationshipRemove = _ctrl<Map<String, dynamic>>();

  late final _auditLogCreate = _ctrl<Map<String, dynamic>>();
  late final _anonymousCountUpdated = _ctrl<Map<String, dynamic>>();
  late final _rawEvent = _ctrl<RawGatewayEvent>();

  Stream<void> get onConnected => _connected.stream;
  Stream<DisconnectInfo> get onDisconnected => _disconnected.stream;
  Stream<ReconnectInfo> get onReconnecting => _reconnecting.stream;
  Stream<Map<String, dynamic>> get onReady => _readyReceived.stream;
  Stream<void> get onResumed => _resumed.stream;

  Stream<AccordSpace> get onSpaceCreate => _spaceCreate.stream;
  Stream<AccordSpace> get onSpaceUpdate => _spaceUpdate.stream;
  Stream<Map<String, dynamic>> get onSpaceDelete => _spaceDelete.stream;

  Stream<AccordChannel> get onChannelCreate => _channelCreate.stream;
  Stream<AccordChannel> get onChannelUpdate => _channelUpdate.stream;
  Stream<AccordChannel> get onChannelDelete => _channelDelete.stream;
  Stream<Map<String, dynamic>> get onChannelReorder => _channelReorder.stream;
  Stream<Map<String, dynamic>> get onChannelPinsUpdate =>
      _channelPinsUpdate.stream;
  Stream<Map<String, dynamic>> get onChannelMuteCreate =>
      _channelMuteCreate.stream;
  Stream<Map<String, dynamic>> get onChannelMuteDelete =>
      _channelMuteDelete.stream;

  Stream<AccordMember> get onMemberJoin => _memberJoin.stream;
  Stream<Map<String, dynamic>> get onMemberLeave => _memberLeave.stream;
  Stream<AccordMember> get onMemberUpdate => _memberUpdate.stream;
  Stream<Map<String, dynamic>> get onMemberChunk => _memberChunk.stream;

  Stream<Map<String, dynamic>> get onRoleCreate => _roleCreate.stream;
  Stream<Map<String, dynamic>> get onRoleUpdate => _roleUpdate.stream;
  Stream<Map<String, dynamic>> get onRoleDelete => _roleDelete.stream;

  Stream<AccordMessage> get onMessageCreate => _messageCreate.stream;
  Stream<AccordMessage> get onMessageUpdate => _messageUpdate.stream;
  Stream<Map<String, dynamic>> get onMessageDelete => _messageDelete.stream;
  Stream<Map<String, dynamic>> get onMessageDeleteBulk =>
      _messageDeleteBulk.stream;

  /// Fired when the server reports that the authenticated user read a channel on
  /// another session (multi-device sync). Carries `channel_id`,
  /// `last_read_message_id`, and `mention_count`.
  Stream<Map<String, dynamic>> get onReadStateUpdate =>
      _readStateUpdate.stream;

  Stream<Map<String, dynamic>> get onReactionAdd => _reactionAdd.stream;
  Stream<Map<String, dynamic>> get onReactionRemove => _reactionRemove.stream;
  Stream<Map<String, dynamic>> get onReactionClear => _reactionClear.stream;
  Stream<Map<String, dynamic>> get onReactionClearEmoji =>
      _reactionClearEmoji.stream;

  Stream<AccordPresence> get onPresenceUpdate => _presenceUpdate.stream;
  Stream<Map<String, dynamic>> get onTypingStart => _typingStart.stream;

  Stream<AccordUser> get onUserUpdate => _userUpdate.stream;

  Stream<AccordVoiceState> get onVoiceStateUpdate => _voiceStateUpdate.stream;
  Stream<AccordVoiceServerUpdate> get onVoiceServerUpdate =>
      _voiceServerUpdate.stream;
  Stream<Map<String, dynamic>> get onVoiceSignal => _voiceSignal.stream;

  Stream<AccordCallSignal> get onCallRing => _callRing.stream;
  Stream<AccordCallSignal> get onCallDecline => _callDecline.stream;
  Stream<AccordCallSignal> get onCallCancel => _callCancel.stream;
  Stream<AccordCallSignal> get onCallEnd => _callEnd.stream;

  Stream<Map<String, dynamic>> get onBanCreate => _banCreate.stream;
  Stream<Map<String, dynamic>> get onBanDelete => _banDelete.stream;

  Stream<Map<String, dynamic>> get onReportCreate => _reportCreate.stream;

  Stream<AccordInvite> get onInviteCreate => _inviteCreate.stream;
  Stream<Map<String, dynamic>> get onInviteDelete => _inviteDelete.stream;

  Stream<AccordInteraction> get onInteractionCreate =>
      _interactionCreate.stream;

  Stream<Map<String, dynamic>> get onPluginInstalled => _pluginInstalled.stream;
  Stream<Map<String, dynamic>> get onPluginUninstalled =>
      _pluginUninstalled.stream;
  Stream<Map<String, dynamic>> get onPluginEvent => _pluginEvent.stream;
  Stream<Map<String, dynamic>> get onPluginSessionState =>
      _pluginSessionState.stream;
  Stream<Map<String, dynamic>> get onPluginRoleChanged =>
      _pluginRoleChanged.stream;
  Stream<Map<String, dynamic>> get onPluginLeaderboardUpdated =>
      _pluginLeaderboardUpdated.stream;

  Stream<Map<String, dynamic>> get onEmojiCreate => _emojiCreate.stream;
  Stream<Map<String, dynamic>> get onEmojiUpdate => _emojiUpdate.stream;
  Stream<Map<String, dynamic>> get onEmojiDelete => _emojiDelete.stream;

  Stream<AccordSound> get onSoundboardCreate => _soundboardCreate.stream;
  Stream<AccordSound> get onSoundboardUpdate => _soundboardUpdate.stream;
  Stream<Map<String, dynamic>> get onSoundboardDelete =>
      _soundboardDelete.stream;
  Stream<Map<String, dynamic>> get onSoundboardPlay => _soundboardPlay.stream;

  Stream<AccordRelationship> get onRelationshipAdd => _relationshipAdd.stream;
  Stream<AccordRelationship> get onRelationshipUpdate =>
      _relationshipUpdate.stream;
  Stream<Map<String, dynamic>> get onRelationshipRemove =>
      _relationshipRemove.stream;

  Stream<Map<String, dynamic>> get onAuditLogCreate => _auditLogCreate.stream;
  Stream<Map<String, dynamic>> get onAnonymousCountUpdated =>
      _anonymousCountUpdated.stream;
  Stream<RawGatewayEvent> get onRawEvent => _rawEvent.stream;

  // ── Public API ─────────────────────────────────────────────────────────

  /// Current lifecycle state.
  GatewayState get state => _state;

  /// Current resumable session ID (empty when none).
  String get sessionId => _sessionId;

  /// The effective heartbeat interval in ms, after capping the server-advertised
  /// value at [AccordConfig.heartbeatIntervalMax]. Set on HELLO.
  int get heartbeatIntervalMs => _heartbeatIntervalMs;

  /// Configures the socket before connecting.
  void setup(
    AccordConfig config,
    String tkn, {
    String tknType = 'Bot',
    List<String> intentList = const [],
  }) {
    _config = config;
    token = tkn;
    tokenType = tknType;
    intents = intentList.isNotEmpty ? intentList : GatewayIntents.defaults();
  }

  /// Opens the gateway connection. No-op unless currently disconnected.
  void connectToGateway([String url = '']) {
    if (_state != GatewayState.disconnected) return;
    final config = _config;
    _gatewayUrl = url.isNotEmpty
        ? url
        : (config != null ? config.gatewayConnectUrl() : '');
    _reconnectAttempts = 0;
    _reconnectCancelled = false;
    _openConnection(GatewayState.connecting);
  }

  /// Closes the gateway connection and suppresses reconnects.
  Future<void> disconnectFromGateway(
      [int code = 1000, String reason = 'client disconnect']) async {
    _reconnectCancelled = true;
    if (_state == GatewayState.disconnected) return;
    _state = GatewayState.disconnected;
    _stopHeartbeat();
    final conn = _conn;
    await _sub?.cancel();
    _sub = null;
    await conn?.close(code, reason);
    _disconnected.add(DisconnectInfo(code, reason));
  }

  /// Verifies the connection is alive and revives it if not. Call after a
  /// period of process suspension (e.g. the app returning to the foreground on
  /// mobile, where the OS freezes timers and silently kills sockets).
  ///
  /// - Disconnected: reconnects immediately with a fresh backoff budget, even
  ///   when earlier automatic reconnects exhausted [maxReconnectAttempts].
  ///   Resumes the previous session when one is held, else re-identifies.
  /// - Nominally connected: the socket may be dead without a close frame ever
  ///   having been delivered, so send an out-of-band heartbeat and force-close
  ///   (triggering the normal reconnect path) if no ACK arrives within
  ///   [probeTimeout].
  ///
  /// No-op before [connectToGateway] is first called or after an explicit
  /// [disconnectFromGateway]/[dispose] — being offline is then intentional.
  void ensureConnected() {
    if (_reconnectCancelled || _gatewayUrl.isEmpty) return;
    if (_state == GatewayState.disconnected) {
      _reconnectAttempts = 0;
      _openConnection(_sessionId.isNotEmpty
          ? GatewayState.resuming
          : GatewayState.connecting);
      return;
    }
    // Only probe a fully-established connection; if we're mid-handshake
    // (connecting/resuming) the existing attempt is already in progress.
    if (_state != GatewayState.connected) return;
    unawaited(_probeLiveness());
  }

  Future<void> _probeLiveness() async {
    if (_probePending) return;
    _probePending = true;
    // Stop the heartbeat timer for the duration of the probe. Without this,
    // the timer can fire while _heartbeatAckReceived is false (reset below)
    // and close a live connection before the probe ACK arrives.
    _stopHeartbeat();
    try {
      _heartbeatAckReceived = false;
      _send({'op': GatewayOpcodes.heartbeat, 'data': _sequence});
      await _sleep(probeTimeout);
      if (_heartbeatAckReceived) {
        // Connection is alive; resume normal heartbeating.
        _startHeartbeat();
        return;
      }
      if (_reconnectCancelled || _state == GatewayState.disconnected) return;
      _conn?.close(4000, 'liveness probe timeout');
    } finally {
      _probePending = false;
    }
  }

  /// Sends a presence update.
  void updatePresence(String status,
      {Map<String, dynamic> activity = const {}}) {
    final data = <String, dynamic>{'status': status};
    if (activity.isNotEmpty) data['activity'] = activity;
    _send({'op': GatewayOpcodes.presenceUpdate, 'data': data});
  }

  /// Sends a voice state update. [channelId] may be null to disconnect.
  ///
  /// [spaceId] is null for DM and group DM calls, which have no parent space —
  /// the server resolves the scope from the channel and routes the update to
  /// the call's participants. When non-null it must be the channel's own space;
  /// the server ignores an update that claims a different one.
  void updateVoiceState(
    String? spaceId,
    String? channelId, {
    bool selfMute = false,
    bool selfDeaf = false,
    bool selfVideo = false,
    bool selfStream = false,
  }) {
    _send({
      'op': GatewayOpcodes.voiceStateUpdate,
      'data': {
        'space_id': spaceId,
        'channel_id': channelId,
        'self_mute': selfMute,
        'self_deaf': selfDeaf,
        'self_video': selfVideo,
        'self_stream': selfStream,
      },
    });
  }

  /// Requests the member list (or a filtered subset) for a space.
  void requestMembers(String spaceId, {String query = '', int limit = 0}) {
    _send({
      'op': GatewayOpcodes.requestMembers,
      'data': {'space_id': spaceId, 'query': query, 'limit': limit},
    });
  }

  /// Sends a voice signalling payload through the gateway.
  void sendVoiceSignal(String spaceId, String channelId, String signalType,
      Map<String, dynamic> payload) {
    _send({
      'op': GatewayOpcodes.voiceSignal,
      'data': {
        'space_id': spaceId,
        'channel_id': channelId,
        'type': signalType,
        'payload': payload,
      },
    });
  }

  /// Closes all event streams and tears down the connection. The socket cannot
  /// be reused after calling this.
  Future<void> dispose() async {
    _reconnectCancelled = true;
    _stopHeartbeat();
    await _sub?.cancel();
    _sub = null;
    // 1000 (normal closure) is the only RFC 6455 code the dart `web_socket`
    // package permits an application to send; 1001 ("going away") is reserved
    // and throws ArgumentError when passed to WebSocketChannel.sink.close.
    await _conn?.close(1000, 'going away');
    _conn = null;
    for (final c in _controllers) {
      await c.close();
    }
  }

  // ── Connection management ────────────────────────────────────────────────

  void _openConnection(GatewayState initialState) {
    _teardownConnection();
    _state = initialState;
    final conn = _factory(_gatewayUrl);
    _conn = conn;
    _sub = conn.messages.listen(
      _handleMessage,
      onDone: _onClosed,
      onError: (_) {},
      cancelOnError: false,
    );
    conn.ready.then((_) {
      if (_state == GatewayState.connecting) {
        _state = GatewayState.connected;
        _connected.add(null);
      }
    }).catchError((_) {
      // Failure surfaces via the stream's onDone/onError → _onClosed.
    });
  }

  void _teardownConnection() {
    _sub?.cancel();
    _sub = null;
    _conn?.close();
    _conn = null;
  }

  void _onClosed() {
    final code = _conn?.closeCode ?? 1006;
    final reason = _conn?.closeReason ?? '';
    if (_resumePending) {
      _sessionId = '';
      _sequence = 0;
      _resumePending = false;
    }
    _stopHeartbeat();
    final wasDisconnected = _state == GatewayState.disconnected;
    _state = GatewayState.disconnected;
    if (!wasDisconnected) {
      _disconnected.add(DisconnectInfo(code, reason));
    }
    if (!_reconnectCancelled && _shouldReconnect(code)) {
      _attemptReconnect();
    }
  }

  bool _shouldReconnect(int code) {
    const fatalCodes = [4003, 4004, 4012, 4013, 4014];
    if (fatalCodes.contains(code)) return false;
    return _reconnectAttempts < maxReconnectAttempts;
  }

  Future<void> _attemptReconnect() async {
    _reconnectAttempts += 1;
    _reconnecting.add(ReconnectInfo(_reconnectAttempts, maxReconnectAttempts));
    // Exponential backoff with jitter: base * 2^attempt + random jitter.
    const baseDelay = 1.0;
    final delay =
        baseDelay * pow(2.0, min(_reconnectAttempts - 1, 5)) + _random();
    await _sleep(Duration(milliseconds: (delay * 1000).round()));
    if (_reconnectCancelled) return;
    final initial =
        _sessionId.isNotEmpty ? GatewayState.resuming : GatewayState.connecting;
    _openConnection(initial);
  }

  // ── Heartbeat ────────────────────────────────────────────────────────────

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(
      Duration(milliseconds: _heartbeatIntervalMs),
      (_) => _sendHeartbeat(),
    );
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _sendHeartbeat() {
    if (!_heartbeatAckReceived) {
      // No ACK since the last beat — the connection is stale.
      _conn?.close(4000, 'heartbeat timeout');
      return;
    }
    _heartbeatAckReceived = false;
    _send({'op': GatewayOpcodes.heartbeat, 'data': _sequence});
  }

  // ── Outbound ─────────────────────────────────────────────────────────────

  void _send(Map<String, dynamic> payload) {
    _conn?.sendText(jsonEncode(payload));
  }

  void _sendIdentify() {
    _send({
      'op': GatewayOpcodes.identify,
      'data': {
        'token': '$tokenType $token',
        'intents': intents,
        'properties': {
          'os': _osName,
          'client': 'AccordKit',
          'version': AccordConfig.clientVersion,
        },
      },
    });
  }

  void _sendResume() {
    _state = GatewayState.resuming;
    _resumePending = true;
    _send({
      'op': GatewayOpcodes.resume,
      'data': {
        'token': '$tokenType $token',
        'session_id': _sessionId,
        'seq': _sequence,
      },
    });
  }

  // ── Inbound ──────────────────────────────────────────────────────────────

  void _handleMessage(String text) {
    Object? parsed;
    try {
      parsed = jsonDecode(text);
    } catch (_) {
      return;
    }
    if (parsed is! Map) return;
    final map = parsed.cast<String, dynamic>();

    final op = asInt(map['op'], -1);
    final data = map['data'];
    final seq = map['seq'];
    final eventType = asString(map['type']);

    if (seq is num) {
      _sequence = seq.toInt();
    }

    switch (op) {
      case GatewayOpcodes.hello:
        final dataMap = asMap(data) ?? const {};
        // Cap the advertised interval: the heartbeat is our only keepalive on an
        // idle socket, and intervals longer than a middlebox's idle timeout let
        // the connection get culled (close 1006) before a beat fires. See
        // [AccordConfig.heartbeatIntervalMax].
        _heartbeatIntervalMs = min(
          asInt(dataMap['heartbeat_interval'],
              AccordConfig.heartbeatIntervalDefault),
          AccordConfig.heartbeatIntervalMax,
        );
        _heartbeatAckReceived = true;
        _startHeartbeat();
        if (_sessionId.isNotEmpty && _state == GatewayState.resuming) {
          _sendResume();
        } else {
          _sendIdentify();
        }
        break;

      case GatewayOpcodes.heartbeatAck:
        _heartbeatAckReceived = true;
        break;

      case GatewayOpcodes.heartbeat:
        _sendHeartbeat();
        break;

      case GatewayOpcodes.reconnect:
        _conn?.close(4000, 'server requested reconnect');
        break;

      case GatewayOpcodes.invalidSession:
        _handleInvalidSession(data);
        break;

      case GatewayOpcodes.event:
        _dispatchEvent(eventType, asMap(data) ?? const {});
        break;
    }
  }

  Future<void> _handleInvalidSession(Object? data) async {
    final resumable = data is bool ? data : false;
    if (!resumable) {
      _sessionId = '';
      _sequence = 0;
    }
    if (_reconnectAttempts >= maxReconnectAttempts) {
      _state = GatewayState.disconnected;
      _stopHeartbeat();
      await _conn?.close(1000, 'max reconnect attempts');
      _disconnected.add(
          const DisconnectInfo(4004, 'session invalid after max attempts'));
      return;
    }
    // Wait 1–5 seconds, then reconnect.
    await _sleep(Duration(milliseconds: (1000 + _random() * 4000).round()));
    if (_reconnectCancelled) return;
    _attemptReconnect();
  }

  void _dispatchEvent(String eventType, Map<String, dynamic> data) {
    switch (eventType) {
      case 'ready':
        _sessionId = asString(data['session_id']);
        _reconnectAttempts = 0;
        _resumePending = false;
        _readyReceived.add(data);
        break;
      case 'resumed':
        _reconnectAttempts = 0;
        _resumePending = false;
        _resumed.add(null);
        break;
      case 'space.create':
        _spaceCreate.add(AccordSpace.fromJson(data));
        break;
      case 'space.update':
        _spaceUpdate.add(AccordSpace.fromJson(data));
        break;
      case 'space.delete':
        _spaceDelete.add(data);
        break;
      case 'channel.create':
        _channelCreate.add(AccordChannel.fromJson(data));
        break;
      case 'channel.update':
        _channelUpdate.add(AccordChannel.fromJson(data));
        break;
      case 'channel.delete':
        _channelDelete.add(AccordChannel.fromJson(data));
        break;
      case 'channel.reorder':
        _channelReorder.add(data);
        break;
      case 'channel.pins_update':
        _channelPinsUpdate.add(data);
        break;
      case 'channel_mute.create':
        _channelMuteCreate.add(data);
        break;
      case 'channel_mute.delete':
        _channelMuteDelete.add(data);
        break;
      case 'member.join':
        _memberJoin.add(AccordMember.fromJson(data));
        break;
      case 'member.leave':
        _memberLeave.add(data);
        break;
      case 'member.update':
        _memberUpdate.add(AccordMember.fromJson(data));
        break;
      case 'member.chunk':
        _memberChunk.add(data);
        break;
      case 'role.create':
        _roleCreate.add(data);
        break;
      case 'role.update':
        _roleUpdate.add(data);
        break;
      case 'role.delete':
        _roleDelete.add(data);
        break;
      case 'message.create':
        _messageCreate.add(AccordMessage.fromJson(data));
        break;
      case 'message.update':
        _messageUpdate.add(AccordMessage.fromJson(data));
        break;
      case 'message.delete':
        _messageDelete.add(data);
        break;
      case 'message.delete_bulk':
        _messageDeleteBulk.add(data);
        break;
      case 'read_state.update':
        _readStateUpdate.add(data);
        break;
      case 'reaction.add':
        _reactionAdd.add(data);
        break;
      case 'reaction.remove':
        _reactionRemove.add(data);
        break;
      case 'reaction.clear':
        _reactionClear.add(data);
        break;
      case 'reaction.clear_emoji':
        _reactionClearEmoji.add(data);
        break;
      case 'presence.update':
        _presenceUpdate.add(AccordPresence.fromJson(data));
        break;
      case 'typing.start':
        _typingStart.add(data);
        break;
      case 'user.update':
        _userUpdate.add(AccordUser.fromJson(data));
        break;
      case 'voice.state_update':
        _voiceStateUpdate.add(AccordVoiceState.fromJson(data));
        break;
      case 'voice.server_update':
        _voiceServerUpdate.add(AccordVoiceServerUpdate.fromJson(data));
        break;
      case 'voice.signal':
        _voiceSignal.add(data);
        break;
      case 'call.ring':
        _callRing.add(AccordCallSignal.fromJson(data, type: 'ring'));
        break;
      case 'call.decline':
        _callDecline.add(AccordCallSignal.fromJson(data, type: 'decline'));
        break;
      case 'call.cancel':
        _callCancel.add(AccordCallSignal.fromJson(data, type: 'cancel'));
        break;
      case 'call.end':
        _callEnd.add(AccordCallSignal.fromJson(data, type: 'end'));
        break;
      case 'ban.create':
        _banCreate.add(data);
        break;
      case 'ban.delete':
        _banDelete.add(data);
        break;
      case 'report.create':
        _reportCreate.add(data);
        break;
      case 'invite.create':
        _inviteCreate.add(AccordInvite.fromJson(data));
        break;
      case 'invite.delete':
        _inviteDelete.add(data);
        break;
      case 'interaction.create':
        _interactionCreate.add(AccordInteraction.fromJson(data));
        break;
      case 'plugin.installed':
        _pluginInstalled.add(data);
        break;
      case 'plugin.uninstalled':
        _pluginUninstalled.add(data);
        break;
      case 'plugin.event':
        _pluginEvent.add(data);
        break;
      case 'plugin.session_state':
        _pluginSessionState.add(data);
        break;
      case 'plugin.role_changed':
        _pluginRoleChanged.add(data);
        break;
      case 'plugin.leaderboard_updated':
        _pluginLeaderboardUpdated.add(data);
        break;
      case 'anonymous_count.update':
        _anonymousCountUpdated.add(data);
        break;
      case 'emoji.create':
        _emojiCreate.add(data);
        break;
      case 'emoji.update':
        _emojiUpdate.add(data);
        break;
      case 'emoji.delete':
        _emojiDelete.add(data);
        break;
      case 'soundboard.create':
        _soundboardCreate.add(AccordSound.fromJson(data));
        break;
      case 'soundboard.update':
        _soundboardUpdate.add(AccordSound.fromJson(data));
        break;
      case 'soundboard.delete':
        _soundboardDelete.add(data);
        break;
      case 'soundboard.play':
        _soundboardPlay.add(data);
        break;
      case 'relationship.add':
        _relationshipAdd.add(AccordRelationship.fromJson(data));
        break;
      case 'relationship.update':
        _relationshipUpdate.add(AccordRelationship.fromJson(data));
        break;
      case 'relationship.remove':
        _relationshipRemove.add(data);
        break;
      case 'audit_log.create':
        _auditLogCreate.add(data);
        break;
    }

    _rawEvent.add(RawGatewayEvent(eventType, data));
  }
}
