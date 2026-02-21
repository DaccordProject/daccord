class_name GatewayIntents extends RefCounted

const SPACES := "spaces"
const MODERATION := "moderation"
const EMOJIS := "emojis"
const VOICE_STATES := "voice_states"
const MESSAGES := "messages"
const MESSAGE_REACTIONS := "message_reactions"
const MESSAGE_TYPING := "message_typing"
const DIRECT_MESSAGES := "direct_messages"
const DM_REACTIONS := "dm_reactions"
const DM_TYPING := "dm_typing"
const SCHEDULED_EVENTS := "scheduled_events"

# Privileged intents
const MEMBERS := "members"
const PRESENCES := "presences"
const MESSAGE_CONTENT := "message_content"

static func unprivileged() -> Array:
	return [
		SPACES, MODERATION, EMOJIS, VOICE_STATES,
		MESSAGES, MESSAGE_REACTIONS, MESSAGE_TYPING,
		DIRECT_MESSAGES, DM_REACTIONS, DM_TYPING,
		SCHEDULED_EVENTS,
	]

static func privileged() -> Array:
	return [MEMBERS, PRESENCES, MESSAGE_CONTENT]

static func all() -> Array:
	return unprivileged() + privileged()

static func default() -> Array:
	return [SPACES, MESSAGES, MESSAGE_CONTENT]
