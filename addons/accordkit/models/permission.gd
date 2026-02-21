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
	]


static func has(permissions: Array, perm: String) -> bool:
	return perm in permissions or ADMINISTRATOR in permissions
