class_name AccordPermission
extends RefCounted

## Permission string constants.

const CREATE_INVITES := "create_invites"
const KICK_MEMBERS := "kick_members"
const BAN_MEMBERS := "ban_members"
const ADMINISTRATOR := "administrator"
const MANAGE_CHANNELS := "manage_channels"
const MANAGE_SPACE := "manage_space"
const ADD_REACTIONS := "add_reactions"
const VIEW_AUDIT_LOG := "view_audit_log"
const PRIORITY_SPEAKER := "priority_speaker"
const STREAM := "stream"
const VIEW_CHANNEL := "view_channel"
const SEND_MESSAGES := "send_messages"
const SEND_TTS := "send_tts"
const MANAGE_MESSAGES := "manage_messages"
const EMBED_LINKS := "embed_links"
const ATTACH_FILES := "attach_files"
const READ_HISTORY := "read_history"
const MENTION_EVERYONE := "mention_everyone"
const USE_EXTERNAL_EMOJIS := "use_external_emojis"
const CONNECT := "connect"
const SPEAK := "speak"
const MUTE_MEMBERS := "mute_members"
const DEAFEN_MEMBERS := "deafen_members"
const MOVE_MEMBERS := "move_members"
const USE_VAD := "use_vad"
const CHANGE_NICKNAME := "change_nickname"
const MANAGE_NICKNAMES := "manage_nicknames"
const MANAGE_ROLES := "manage_roles"
const MANAGE_WEBHOOKS := "manage_webhooks"
const MANAGE_EMOJIS := "manage_emojis"
const MANAGE_SOUNDBOARD := "manage_soundboard"
const USE_SOUNDBOARD := "use_soundboard"
const USE_COMMANDS := "use_commands"
const MANAGE_EVENTS := "manage_events"
const MANAGE_THREADS := "manage_threads"
const CREATE_THREADS := "create_threads"
const USE_EXTERNAL_STICKERS := "use_external_stickers"
const SEND_IN_THREADS := "send_in_threads"
const MODERATE_MEMBERS := "moderate_members"
const MANAGE_AUTOMOD := "manage_automod"


static func all() -> Array:
	return [
		CREATE_INVITES,
		KICK_MEMBERS,
		BAN_MEMBERS,
		ADMINISTRATOR,
		MANAGE_CHANNELS,
		MANAGE_SPACE,
		ADD_REACTIONS,
		VIEW_AUDIT_LOG,
		PRIORITY_SPEAKER,
		STREAM,
		VIEW_CHANNEL,
		SEND_MESSAGES,
		SEND_TTS,
		MANAGE_MESSAGES,
		EMBED_LINKS,
		ATTACH_FILES,
		READ_HISTORY,
		MENTION_EVERYONE,
		USE_EXTERNAL_EMOJIS,
		CONNECT,
		SPEAK,
		MUTE_MEMBERS,
		DEAFEN_MEMBERS,
		MOVE_MEMBERS,
		USE_VAD,
		CHANGE_NICKNAME,
		MANAGE_NICKNAMES,
		MANAGE_ROLES,
		MANAGE_WEBHOOKS,
		MANAGE_EMOJIS,
		MANAGE_SOUNDBOARD,
		USE_SOUNDBOARD,
		USE_COMMANDS,
		MANAGE_EVENTS,
		MANAGE_THREADS,
		CREATE_THREADS,
		USE_EXTERNAL_STICKERS,
		SEND_IN_THREADS,
		MODERATE_MEMBERS,
		MANAGE_AUTOMOD,
	]


static func has(permissions: Array, perm: String) -> bool:
	return perm in permissions or ADMINISTRATOR in permissions


static func description(perm: String) -> String:
	match perm:
		CREATE_INVITES: return "Allows creating invite links to the space"
		KICK_MEMBERS: return "Allows kicking members from the space"
		BAN_MEMBERS: return "Allows banning members from the space"
		ADMINISTRATOR: return "Grants all permissions and bypasses all checks"
		MANAGE_CHANNELS: return "Allows creating, editing, and deleting channels"
		MANAGE_SPACE: return "Allows editing space name, icon, and settings"
		ADD_REACTIONS: return "Allows adding reactions to messages"
		VIEW_AUDIT_LOG: return "Allows viewing the audit log"
		PRIORITY_SPEAKER: return "Allows being heard over other users in voice"
		STREAM: return "Allows screen sharing in voice channels"
		VIEW_CHANNEL: return "Allows viewing a channel"
		SEND_MESSAGES: return "Allows sending messages in text channels"
		SEND_TTS: return "Allows sending text-to-speech messages"
		MANAGE_MESSAGES: return "Allows deleting and pinning messages from other users"
		EMBED_LINKS: return "Allows link previews to be shown for sent messages"
		ATTACH_FILES: return "Allows uploading files and images"
		READ_HISTORY: return "Allows reading message history"
		MENTION_EVERYONE: return "Allows using @everyone and @here mentions"
		USE_EXTERNAL_EMOJIS: return "Allows using emojis from other spaces"
		CONNECT: return "Allows joining voice channels"
		SPEAK: return "Allows speaking in voice channels"
		MUTE_MEMBERS: return "Allows muting other members in voice channels"
		DEAFEN_MEMBERS: return "Allows deafening other members in voice channels"
		MOVE_MEMBERS: return "Allows moving members between voice channels"
		USE_VAD: return "Allows using voice activity detection instead of push-to-talk"
		CHANGE_NICKNAME: return "Allows changing own nickname"
		MANAGE_NICKNAMES: return "Allows changing nicknames of other members"
		MANAGE_ROLES: return "Allows creating and editing roles below their highest role"
		MANAGE_WEBHOOKS: return "Allows creating, editing, and deleting webhooks"
		MANAGE_EMOJIS: return "Allows managing custom emojis"
		MANAGE_SOUNDBOARD: return "Allows managing soundboard sounds"
		USE_SOUNDBOARD: return "Allows playing soundboard sounds"
		USE_COMMANDS: return "Allows using bot and slash commands"
		MANAGE_EVENTS: return "Allows creating, editing, and deleting events"
		MANAGE_THREADS: return "Allows managing threads and forum posts"
		CREATE_THREADS: return "Allows creating threads and forum posts"
		USE_EXTERNAL_STICKERS: return "Allows using stickers from other spaces"
		SEND_IN_THREADS: return "Allows sending messages in threads"
		MODERATE_MEMBERS: return "Allows timing out and moderating members"
		MANAGE_AUTOMOD: return "Allows configuring auto-moderation rules"
	return ""
