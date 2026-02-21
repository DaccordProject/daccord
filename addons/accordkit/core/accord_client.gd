class_name AccordClient extends Node

# Connection
signal connected
signal disconnected(code: int, reason: String)
signal reconnecting(attempt: int, max_attempts: int)
signal ready_received(data: Dictionary)
signal resumed

# Spaces
signal space_create(space: AccordSpace)
signal space_update(space: AccordSpace)
signal space_delete(data: Dictionary)

# Channels
signal channel_create(channel: AccordChannel)
signal channel_update(channel: AccordChannel)
signal channel_delete(channel: AccordChannel)
signal channel_pins_update(data: Dictionary)

# Members
signal member_join(member: AccordMember)
signal member_leave(data: Dictionary)
signal member_update(member: AccordMember)
signal member_chunk(data: Dictionary)

# Roles
signal role_create(data: Dictionary)
signal role_update(data: Dictionary)
signal role_delete(data: Dictionary)

# Messages
signal message_create(message: AccordMessage)
signal message_update(message: AccordMessage)
signal message_delete(data: Dictionary)
signal message_delete_bulk(data: Dictionary)

# Reactions
signal reaction_add(data: Dictionary)
signal reaction_remove(data: Dictionary)
signal reaction_clear(data: Dictionary)
signal reaction_clear_emoji(data: Dictionary)

# Presence
signal presence_update(presence: AccordPresence)
signal typing_start(data: Dictionary)

# User
signal user_update(user: AccordUser)

# Voice
signal voice_state_update(state: AccordVoiceState)
signal voice_server_update(info: AccordVoiceServerUpdate)
signal voice_signal(data: Dictionary)

# Bans
signal ban_create(data: Dictionary)
signal ban_delete(data: Dictionary)

# Invites
signal invite_create(invite: AccordInvite)
signal invite_delete(data: Dictionary)

# Interactions
signal interaction_create(interaction: AccordInteraction)

# Emojis
signal emoji_create(data: Dictionary)
signal emoji_update(data: Dictionary)
signal emoji_delete(data: Dictionary)

# Soundboard
signal soundboard_create(sound: AccordSound)
signal soundboard_update(sound: AccordSound)
signal soundboard_delete(data: Dictionary)
signal soundboard_play(data: Dictionary)

# Raw
signal raw_event(event_type: String, data: Dictionary)

@export var token: String = ""
@export var token_type: String = "Bot"
@export var intents: Array = []
@export var base_url: String = AccordConfig.DEFAULT_BASE_URL
@export var gateway_url: String = AccordConfig.DEFAULT_GATEWAY_URL
@export var cdn_url: String = AccordConfig.DEFAULT_CDN_URL

var config: AccordConfig
var rest: AccordRest
var gateway: GatewaySocket

# Namespaced endpoint APIs
var users: UsersApi
var spaces: SpacesApi
var channels: ChannelsApi
var messages: MessagesApi
var members: MembersApi
var roles: RolesApi
var bans: BansApi
var invites: InvitesApi
var emojis: EmojisApi
var soundboard: SoundboardApi
var reactions: ReactionsApi
var interactions: InteractionsApi
var applications: ApplicationsApi
var auth: AuthApi
var voice: VoiceApi
var audit_logs: AuditLogsApi
var voice_manager: VoiceManager


func _ready() -> void:
	config = AccordConfig.new()
	config.base_url = base_url
	config.gateway_url = gateway_url
	config.cdn_url = cdn_url

	# REST
	rest = AccordRest.new(config.api_url())
	rest.token = token
	rest.token_type = token_type
	add_child(rest)

	# Endpoint APIs
	users = UsersApi.new(rest)
	spaces = SpacesApi.new(rest)
	channels = ChannelsApi.new(rest)
	messages = MessagesApi.new(rest)
	members = MembersApi.new(rest)
	roles = RolesApi.new(rest)
	bans = BansApi.new(rest)
	invites = InvitesApi.new(rest)
	emojis = EmojisApi.new(rest)
	soundboard = SoundboardApi.new(rest)
	reactions = ReactionsApi.new(rest)
	interactions = InteractionsApi.new(rest)
	applications = ApplicationsApi.new(rest)
	auth = AuthApi.new(rest)
	voice = VoiceApi.new(rest)
	audit_logs = AuditLogsApi.new(rest)

	# Gateway
	gateway = GatewaySocket.new()
	gateway.name = "GatewaySocket"
	add_child(gateway)
	gateway.setup(config, token, token_type, intents)
	_connect_gateway_signals()

	# Voice manager
	voice_manager = VoiceManager.new(voice, gateway)


func login() -> void:
	gateway.connect_to_gateway()


func logout() -> void:
	gateway.disconnect_from_gateway()


func update_presence(status: String, activity: Dictionary = {}) -> void:
	gateway.update_presence(status, activity)


func update_voice_state(
	space_id: String, channel_id,
	self_mute: bool = false, self_deaf: bool = false,
	self_video: bool = false, self_stream: bool = false,
) -> void:
	gateway.update_voice_state(
		space_id, channel_id, self_mute, self_deaf,
		self_video, self_stream,
	)


func request_members(space_id: String, query: String = "", limit: int = 0) -> void:
	gateway.request_members(space_id, query, limit)


func send_voice_signal(
	space_id: String, channel_id: String,
	signal_type: String, payload: Dictionary,
) -> void:
	gateway.send_voice_signal(space_id, channel_id, signal_type, payload)


func _connect_gateway_signals() -> void:
	gateway.connected.connect(func(): connected.emit())
	gateway.disconnected.connect(func(code, reason): disconnected.emit(code, reason))
	gateway.reconnecting.connect(func(a, m): reconnecting.emit(a, m))
	gateway.ready_received.connect(func(data): ready_received.emit(data))
	gateway.resumed.connect(func(): resumed.emit())

	gateway.space_create.connect(func(s): space_create.emit(s))
	gateway.space_update.connect(func(s): space_update.emit(s))
	gateway.space_delete.connect(func(d): space_delete.emit(d))

	gateway.channel_create.connect(func(c): channel_create.emit(c))
	gateway.channel_update.connect(func(c): channel_update.emit(c))
	gateway.channel_delete.connect(func(c): channel_delete.emit(c))
	gateway.channel_pins_update.connect(func(d): channel_pins_update.emit(d))

	gateway.member_join.connect(func(m): member_join.emit(m))
	gateway.member_leave.connect(func(d): member_leave.emit(d))
	gateway.member_update.connect(func(m): member_update.emit(m))
	gateway.member_chunk.connect(func(d): member_chunk.emit(d))

	gateway.role_create.connect(func(d): role_create.emit(d))
	gateway.role_update.connect(func(d): role_update.emit(d))
	gateway.role_delete.connect(func(d): role_delete.emit(d))

	gateway.message_create.connect(func(m): message_create.emit(m))
	gateway.message_update.connect(func(m): message_update.emit(m))
	gateway.message_delete.connect(func(d): message_delete.emit(d))
	gateway.message_delete_bulk.connect(func(d): message_delete_bulk.emit(d))

	gateway.reaction_add.connect(func(d): reaction_add.emit(d))
	gateway.reaction_remove.connect(func(d): reaction_remove.emit(d))
	gateway.reaction_clear.connect(func(d): reaction_clear.emit(d))
	gateway.reaction_clear_emoji.connect(func(d): reaction_clear_emoji.emit(d))

	gateway.presence_update.connect(func(p): presence_update.emit(p))
	gateway.typing_start.connect(func(d): typing_start.emit(d))

	gateway.user_update.connect(func(u): user_update.emit(u))

	gateway.voice_state_update.connect(func(s): voice_state_update.emit(s))
	gateway.voice_server_update.connect(func(d): voice_server_update.emit(d))
	gateway.voice_signal.connect(func(d): voice_signal.emit(d))

	gateway.ban_create.connect(func(d): ban_create.emit(d))
	gateway.ban_delete.connect(func(d): ban_delete.emit(d))

	gateway.invite_create.connect(func(i): invite_create.emit(i))
	gateway.invite_delete.connect(func(d): invite_delete.emit(d))

	gateway.interaction_create.connect(func(i): interaction_create.emit(i))
	gateway.emoji_create.connect(func(d): emoji_create.emit(d))
	gateway.emoji_update.connect(func(d): emoji_update.emit(d))
	gateway.emoji_delete.connect(func(d): emoji_delete.emit(d))
	gateway.soundboard_create.connect(func(s): soundboard_create.emit(s))
	gateway.soundboard_update.connect(func(s): soundboard_update.emit(s))
	gateway.soundboard_delete.connect(func(d): soundboard_delete.emit(d))
	gateway.soundboard_play.connect(func(d): soundboard_play.emit(d))
	gateway.raw_event.connect(func(t, d): raw_event.emit(t, d))
