import 'package:http/http.dart' as http;

import '../gateway/gateway_connection.dart';
import '../gateway/gateway_events.dart';
import '../gateway/gateway_socket.dart';
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
import '../rest/accord_rest.dart';
import '../rest/endpoints/admin_api.dart';
import '../rest/endpoints/applications_api.dart';
import '../rest/endpoints/audit_logs_api.dart';
import '../rest/endpoints/auth_api.dart';
import '../rest/endpoints/bans_api.dart';
import '../rest/endpoints/channels_api.dart';
import '../rest/endpoints/directory_api.dart';
import '../rest/endpoints/emojis_api.dart';
import '../rest/endpoints/federation_api.dart';
import '../rest/endpoints/interactions_api.dart';
import '../rest/endpoints/invites_api.dart';
import '../rest/endpoints/members_api.dart';
import '../rest/endpoints/messages_api.dart';
import '../rest/endpoints/plugins_api.dart';
import '../rest/endpoints/reactions_api.dart';
import '../rest/endpoints/reports_api.dart';
import '../rest/endpoints/roles_api.dart';
import '../rest/endpoints/soundboard_api.dart';
import '../rest/endpoints/spaces_api.dart';
import '../rest/endpoints/users_api.dart';
import '../rest/endpoints/voice_api.dart';
import '../voice/voice_manager.dart';
import 'accord_config.dart';

/// The top-level AccordKit entry point. Bundles the REST client, the gateway
/// socket, every namespaced endpoint API, and the voice manager.
///
/// Gateway events are exposed both via the [gateway] field and as forwarding
/// getters on the client itself (e.g. [onMessageCreate]).
class AccordClient {
  String token;
  String tokenType;
  List<String> intents;

  final AccordConfig config;
  late final AccordRest rest;
  late final GatewaySocket gateway;

  // Namespaced endpoint APIs.
  late final UsersApi users;
  late final SpacesApi spaces;
  late final ChannelsApi channels;
  late final MessagesApi messages;
  late final MembersApi members;
  late final RolesApi roles;
  late final BansApi bans;
  late final ReportsApi reports;
  late final InvitesApi invites;
  late final EmojisApi emojis;
  late final SoundboardApi soundboard;
  late final ReactionsApi reactions;
  late final InteractionsApi interactions;
  late final PluginsApi plugins;
  late final ApplicationsApi applications;
  late final AuthApi auth;
  late final VoiceApi voice;
  late final AuditLogsApi auditLogs;
  late final AdminApi adminApi;
  late final DirectoryApi directory;
  late final FederationApi federation;
  late final VoiceManager voiceManager;

  AccordClient({
    this.token = '',
    this.tokenType = 'Bot',
    List<String>? intents,
    String? baseUrl,
    String? gatewayUrl,
    String? cdnUrl,
    void Function()? onUnauthorized,
    Duration? requestTimeout,
    Duration? uploadTimeout,
    http.Client? httpClient,
    GatewayConnectionFactory? connectionFactory,
    Future<void> Function(Duration)? sleep,
  })  : intents = intents ?? [],
        config = AccordConfig(
          baseUrl: baseUrl ?? AccordConfig.defaultBaseUrl,
          gatewayUrl: gatewayUrl ?? AccordConfig.defaultGatewayUrl,
          cdnUrl: cdnUrl ?? AccordConfig.defaultCdnUrl,
        ) {
    rest = AccordRest(
      config.apiUrl(),
      token: token,
      tokenType: tokenType,
      onUnauthorized: onUnauthorized,
      timeout: requestTimeout,
      uploadTimeout: uploadTimeout,
      client: httpClient,
      sleep: sleep,
    );

    users = UsersApi(rest);
    spaces = SpacesApi(rest);
    channels = ChannelsApi(rest);
    messages = MessagesApi(rest);
    members = MembersApi(rest);
    roles = RolesApi(rest);
    bans = BansApi(rest);
    reports = ReportsApi(rest);
    invites = InvitesApi(rest);
    emojis = EmojisApi(rest);
    soundboard = SoundboardApi(rest);
    reactions = ReactionsApi(rest);
    interactions = InteractionsApi(rest);
    plugins = PluginsApi(rest);
    applications = ApplicationsApi(rest);
    auth = AuthApi(rest);
    voice = VoiceApi(rest);
    auditLogs = AuditLogsApi(rest);
    adminApi = AdminApi(rest);
    directory = DirectoryApi(rest);
    federation = FederationApi(rest);

    gateway = GatewaySocket(
      connectionFactory: connectionFactory,
      sleep: sleep,
    );
    gateway.setup(config, token, tknType: tokenType, intentList: this.intents);

    voiceManager = VoiceManager(voice, gateway);
  }

  /// Opens the gateway connection.
  void login() => gateway.connectToGateway();

  /// Closes the gateway connection.
  Future<void> logout() => gateway.disconnectFromGateway();

  /// Verifies the gateway connection is alive and revives it if not (see
  /// [GatewaySocket.ensureConnected]). Call when the app returns to the
  /// foreground on platforms that suspend background processes.
  void ensureConnected() => gateway.ensureConnected();

  /// Sends a presence update through the gateway.
  void updatePresence(String status,
          {Map<String, dynamic> activity = const {}}) =>
      gateway.updatePresence(status, activity: activity);

  /// Sends a voice state update through the gateway. [spaceId] is null for DM
  /// and group DM calls, which have no parent space.
  void updateVoiceState(
    String? spaceId,
    String? channelId, {
    bool selfMute = false,
    bool selfDeaf = false,
    bool selfVideo = false,
    bool selfStream = false,
  }) =>
      gateway.updateVoiceState(
        spaceId,
        channelId,
        selfMute: selfMute,
        selfDeaf: selfDeaf,
        selfVideo: selfVideo,
        selfStream: selfStream,
      );

  /// Requests the member list for a space through the gateway.
  void requestMembers(String spaceId, {String query = '', int limit = 0}) =>
      gateway.requestMembers(spaceId, query: query, limit: limit);

  /// Sends a voice signalling payload through the gateway.
  void sendVoiceSignal(String spaceId, String channelId, String signalType,
          Map<String, dynamic> payload) =>
      gateway.sendVoiceSignal(spaceId, channelId, signalType, payload);

  /// Releases the REST client, gateway, and voice manager.
  Future<void> dispose() async {
    await voiceManager.dispose();
    await gateway.dispose();
    rest.close();
  }

  // ── Forwarded gateway event streams ──────────────────────────────────────

  Stream<void> get onConnected => gateway.onConnected;
  Stream<DisconnectInfo> get onDisconnected => gateway.onDisconnected;
  Stream<ReconnectInfo> get onReconnecting => gateway.onReconnecting;
  Stream<Map<String, dynamic>> get onReady => gateway.onReady;
  Stream<void> get onResumed => gateway.onResumed;

  Stream<AccordSpace> get onSpaceCreate => gateway.onSpaceCreate;
  Stream<AccordSpace> get onSpaceUpdate => gateway.onSpaceUpdate;
  Stream<Map<String, dynamic>> get onSpaceDelete => gateway.onSpaceDelete;

  Stream<AccordChannel> get onChannelCreate => gateway.onChannelCreate;
  Stream<AccordChannel> get onChannelUpdate => gateway.onChannelUpdate;
  Stream<AccordChannel> get onChannelDelete => gateway.onChannelDelete;
  Stream<Map<String, dynamic>> get onChannelReorder => gateway.onChannelReorder;
  Stream<Map<String, dynamic>> get onChannelPinsUpdate =>
      gateway.onChannelPinsUpdate;
  Stream<Map<String, dynamic>> get onChannelMuteCreate =>
      gateway.onChannelMuteCreate;
  Stream<Map<String, dynamic>> get onChannelMuteDelete =>
      gateway.onChannelMuteDelete;

  Stream<AccordMember> get onMemberJoin => gateway.onMemberJoin;
  Stream<Map<String, dynamic>> get onMemberLeave => gateway.onMemberLeave;
  Stream<AccordMember> get onMemberUpdate => gateway.onMemberUpdate;
  Stream<Map<String, dynamic>> get onMemberChunk => gateway.onMemberChunk;

  Stream<Map<String, dynamic>> get onRoleCreate => gateway.onRoleCreate;
  Stream<Map<String, dynamic>> get onRoleUpdate => gateway.onRoleUpdate;
  Stream<Map<String, dynamic>> get onRoleDelete => gateway.onRoleDelete;

  Stream<AccordMessage> get onMessageCreate => gateway.onMessageCreate;
  Stream<AccordMessage> get onMessageUpdate => gateway.onMessageUpdate;
  Stream<Map<String, dynamic>> get onMessageDelete => gateway.onMessageDelete;
  Stream<Map<String, dynamic>> get onMessageDeleteBulk =>
      gateway.onMessageDeleteBulk;
  Stream<Map<String, dynamic>> get onReadStateUpdate =>
      gateway.onReadStateUpdate;

  Stream<Map<String, dynamic>> get onReactionAdd => gateway.onReactionAdd;
  Stream<Map<String, dynamic>> get onReactionRemove => gateway.onReactionRemove;
  Stream<Map<String, dynamic>> get onReactionClear => gateway.onReactionClear;
  Stream<Map<String, dynamic>> get onReactionClearEmoji =>
      gateway.onReactionClearEmoji;

  Stream<AccordPresence> get onPresenceUpdate => gateway.onPresenceUpdate;
  Stream<Map<String, dynamic>> get onTypingStart => gateway.onTypingStart;

  Stream<AccordUser> get onUserUpdate => gateway.onUserUpdate;

  Stream<AccordVoiceState> get onVoiceStateUpdate => gateway.onVoiceStateUpdate;
  Stream<AccordVoiceServerUpdate> get onVoiceServerUpdate =>
      gateway.onVoiceServerUpdate;
  Stream<Map<String, dynamic>> get onVoiceSignal => gateway.onVoiceSignal;

  Stream<AccordCallSignal> get onCallRing => gateway.onCallRing;
  Stream<AccordCallSignal> get onCallDecline => gateway.onCallDecline;
  Stream<AccordCallSignal> get onCallCancel => gateway.onCallCancel;
  Stream<AccordCallSignal> get onCallEnd => gateway.onCallEnd;

  Stream<Map<String, dynamic>> get onBanCreate => gateway.onBanCreate;
  Stream<Map<String, dynamic>> get onBanDelete => gateway.onBanDelete;

  Stream<Map<String, dynamic>> get onReportCreate => gateway.onReportCreate;

  Stream<AccordInvite> get onInviteCreate => gateway.onInviteCreate;
  Stream<Map<String, dynamic>> get onInviteDelete => gateway.onInviteDelete;

  Stream<AccordInteraction> get onInteractionCreate =>
      gateway.onInteractionCreate;

  Stream<Map<String, dynamic>> get onPluginInstalled =>
      gateway.onPluginInstalled;
  Stream<Map<String, dynamic>> get onPluginUninstalled =>
      gateway.onPluginUninstalled;
  Stream<Map<String, dynamic>> get onPluginEvent => gateway.onPluginEvent;
  Stream<Map<String, dynamic>> get onPluginSessionState =>
      gateway.onPluginSessionState;
  Stream<Map<String, dynamic>> get onPluginRoleChanged =>
      gateway.onPluginRoleChanged;
  Stream<Map<String, dynamic>> get onPluginLeaderboardUpdated =>
      gateway.onPluginLeaderboardUpdated;

  Stream<Map<String, dynamic>> get onEmojiCreate => gateway.onEmojiCreate;
  Stream<Map<String, dynamic>> get onEmojiUpdate => gateway.onEmojiUpdate;
  Stream<Map<String, dynamic>> get onEmojiDelete => gateway.onEmojiDelete;

  Stream<AccordSound> get onSoundboardCreate => gateway.onSoundboardCreate;
  Stream<AccordSound> get onSoundboardUpdate => gateway.onSoundboardUpdate;
  Stream<Map<String, dynamic>> get onSoundboardDelete =>
      gateway.onSoundboardDelete;
  Stream<Map<String, dynamic>> get onSoundboardPlay => gateway.onSoundboardPlay;

  Stream<AccordRelationship> get onRelationshipAdd => gateway.onRelationshipAdd;
  Stream<AccordRelationship> get onRelationshipUpdate =>
      gateway.onRelationshipUpdate;
  Stream<Map<String, dynamic>> get onRelationshipRemove =>
      gateway.onRelationshipRemove;

  Stream<Map<String, dynamic>> get onAuditLogCreate => gateway.onAuditLogCreate;
  Stream<Map<String, dynamic>> get onAnonymousCountUpdated =>
      gateway.onAnonymousCountUpdated;
  Stream<RawGatewayEvent> get onRawEvent => gateway.onRawEvent;
}
