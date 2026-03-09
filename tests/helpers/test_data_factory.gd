## Shared test data builders. Each method returns a Dictionary with sensible
## defaults that can be overridden via the `overrides` parameter.
extends RefCounted


static func user_data(overrides: Dictionary = {}) -> Dictionary:
	var d := {
		"id": "u_1",
		"display_name": "Alice",
		"username": "alice",
		"color": Color(0.345, 0.396, 0.949),
		"status": 0,
		"avatar": null,
	}
	d.merge(overrides, true)
	return d


static func space_data(overrides: Dictionary = {}) -> Dictionary:
	var d := {
		"id": "g_1",
		"name": "Test Space",
		"icon_color": Color(0.3, 0.5, 0.7),
		"icon": null,
		"unread": false,
		"mentions": 0,
	}
	d.merge(overrides, true)
	return d


static func channel_data(overrides: Dictionary = {}) -> Dictionary:
	var d := {
		"id": "c_1",
		"space_id": "g_1",
		"name": "general",
		"type": ClientModels.ChannelType.TEXT,
		"unread": false,
		"voice_users": 0,
		"nsfw": false,
	}
	d.merge(overrides, true)
	return d


static func category_data(overrides: Dictionary = {}) -> Dictionary:
	var d := {
		"id": "cat_1",
		"space_id": "g_1",
		"name": "Text Channels",
	}
	d.merge(overrides, true)
	return d


static func msg_data(overrides: Dictionary = {}) -> Dictionary:
	var d := {
		"id": "m_1",
		"channel_id": "c_1",
		"author": user_data({"id": "u_author", "color": Color(0.8, 0.2, 0.2)}),
		"content": "Hello world",
		"timestamp": "Today at 2:30 PM",
		"edited": false,
		"reactions": [],
		"reply_to": "",
		"embed": {},
		"embeds": [],
		"attachments": [],
		"system": false,
	}
	d.merge(overrides, true)
	return d


static func dm_data(overrides: Dictionary = {}) -> Dictionary:
	var d := {
		"id": "dm_1",
		"user": {
			"display_name": "Alice",
			"username": "alice",
			"color": Color(0.3, 0.5, 0.8),
		},
		"last_message": "Hey there!",
		"unread": false,
	}
	d.merge(overrides, true)
	return d


static func rel_data(overrides: Dictionary = {}) -> Dictionary:
	var d := {
		"id": "rel_1",
		"user": user_data({"color": Color(0.3, 0.5, 0.8), "status": ClientModels.UserStatus.ONLINE}),
		"type": 1,
		"since": "2025-01-01T00:00:00Z",
	}
	d.merge(overrides, true)
	return d


static func pill_data(overrides: Dictionary = {}) -> Dictionary:
	var d := {
		"emoji": "thumbsup",
		"count": 3,
		"active": false,
		"channel_id": "c_1",
		"message_id": "m_1",
	}
	d.merge(overrides, true)
	return d
