class_name ClientModels

## Converts AccordKit typed models into the dictionary shapes UI components expect.
## Also defines the shared enums that form the data contract between AccordKit and UI.
## Domain-specific logic is delegated to the four sub-modules below.

# Channel types
enum ChannelType { TEXT, VOICE, ANNOUNCEMENT, FORUM, CATEGORY }

# User statuses
enum UserStatus { ONLINE, IDLE, DND, OFFLINE }

# Voice session states (shared between LiveKitAdapter and WebVoiceSession)
enum VoiceSessionState { DISCONNECTED, CONNECTING, CONNECTED, RECONNECTING, FAILED }

const UserModule := preload("res://scripts/client/client_models_user.gd")
const MessageModule := preload("res://scripts/client/client_models_message.gd")
const MemberModule := preload("res://scripts/client/client_models_member.gd")
const SpaceModule := preload("res://scripts/client/client_models_space.gd")

## Known user flag bits and their labels.
const USER_FLAGS := UserModule.USER_FLAGS

# Custom emoji caches — populated by Client when custom emoji are fetched.
# Maps emoji_name -> local cache path (per-profile emoji_cache/{id}.png)
static var custom_emoji_paths: Dictionary = {}
# Maps emoji_name -> Texture2D (in-memory for reaction pills)
static var custom_emoji_textures: Dictionary = {}

static var _hsv_colors := [
	Color.from_hsv(0.0, 0.7, 0.9),
	Color.from_hsv(0.08, 0.7, 0.9),
	Color.from_hsv(0.16, 0.7, 0.9),
	Color.from_hsv(0.28, 0.7, 0.9),
	Color.from_hsv(0.45, 0.7, 0.9),
	Color.from_hsv(0.55, 0.7, 0.9),
	Color.from_hsv(0.65, 0.7, 0.9),
	Color.from_hsv(0.75, 0.7, 0.9),
	Color.from_hsv(0.85, 0.7, 0.9),
	Color.from_hsv(0.95, 0.7, 0.9),
]

## Resolve a media field (avatar/icon/banner) to a full URL, or null.
static func _resolve_media_url(
	raw_value: Variant, owner_id: String, cdn_url: String,
	cdn_builder: Callable = Callable(),
) -> Variant:
	if raw_value == null:
		return null
	var val: String = str(raw_value)
	if val.is_empty():
		return null
	if val.begins_with("/"):
		return AccordCDN.resolve_path(val, cdn_url)
	if cdn_builder.is_valid():
		return cdn_builder.call(owner_id, val, "png", cdn_url)
	return null

static func _color_from_id(id: String) -> Color:
	var count: int = _hsv_colors.size()
	if count == 0:
		return Color.from_hsv(
			absf(float(id.hash()) / float(0x7FFFFFFF)), 0.7, 0.9
		)
	var idx: int = id.hash() % count
	if idx < 0:
		idx += count
	return _hsv_colors[idx]

# --- User delegates ---

static func _status_string_to_enum(s: String) -> int:
	return UserModule._status_string_to_enum(s)

static func _status_enum_to_string(s: int) -> String:
	return UserModule._status_enum_to_string(s)

static func status_color(status: int) -> Color:
	return UserModule.status_color(status)

static func status_label(status: int) -> String:
	return UserModule.status_label(status)

static func user_to_dict(
	user: AccordUser,
	status: int = ClientModels.UserStatus.OFFLINE,
	cdn_url: String = "",
) -> Dictionary:
	return UserModule.user_to_dict(user, status, cdn_url)

static func relationship_to_dict(
	rel: AccordRelationship, cdn_url: String = "",
	server_url: String = "", space_name: String = "",
) -> Dictionary:
	return UserModule.relationship_to_dict(
		rel, cdn_url, server_url, space_name
	)

static func friend_book_entry_to_dict(entry: Dictionary) -> Dictionary:
	return UserModule.friend_book_entry_to_dict(entry)

static func format_activity(activity: Dictionary) -> String:
	return UserModule.format_activity(activity)

static func get_user_badges(flags: int) -> Array:
	return UserModule.get_user_badges(flags)

# --- Message delegates ---

static func _format_timestamp(iso: String) -> String:
	return MessageModule._format_timestamp(iso)

static func message_to_dict(
	msg: AccordMessage, user_cache: Dictionary,
	cdn_url: String = "",
) -> Dictionary:
	return MessageModule.message_to_dict(msg, user_cache, cdn_url)

static func is_user_mentioned(
	data: Dictionary, user_id: String, user_roles: Array,
) -> bool:
	return MessageModule.is_user_mentioned(data, user_id, user_roles)

# --- Member delegates ---

static func member_to_dict(
	member: AccordMember, user_cache: Dictionary,
	cdn_url: String = "",
) -> Dictionary:
	return MemberModule.member_to_dict(member, user_cache, cdn_url)

static func role_to_dict(role: AccordRole) -> Dictionary:
	return MemberModule.role_to_dict(role)

static func voice_state_to_dict(
	state: AccordVoiceState, user_cache: Dictionary,
) -> Dictionary:
	return MemberModule.voice_state_to_dict(state, user_cache)

# --- Space delegates ---

static func _channel_type_to_enum(type_str: String) -> int:
	return SpaceModule._channel_type_to_enum(type_str)

static func space_to_dict(
	space: AccordSpace, cdn_url: String = "",
) -> Dictionary:
	return SpaceModule.space_to_dict(space, cdn_url)

static func channel_to_dict(channel: AccordChannel) -> Dictionary:
	return SpaceModule.channel_to_dict(channel)

static func dm_channel_to_dict(
	channel: AccordChannel, user_cache: Dictionary,
) -> Dictionary:
	return SpaceModule.dm_channel_to_dict(channel, user_cache)

static func invite_to_dict(invite: AccordInvite) -> Dictionary:
	return SpaceModule.invite_to_dict(invite)

static func emoji_to_dict(emoji: AccordEmoji) -> Dictionary:
	return SpaceModule.emoji_to_dict(emoji)

static func sound_to_dict(sound: AccordSound) -> Dictionary:
	return SpaceModule.sound_to_dict(sound)

static func markdown_to_bbcode(text: String) -> String:
	return ClientMarkdown.markdown_to_bbcode(text)
