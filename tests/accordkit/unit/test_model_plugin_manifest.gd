extends GutTest

## Unit tests for AccordPluginManifest model.


func test_from_dict_full() -> void:
	var d := {
		"id": "codenames",
		"name": "Codenames",
		"type": "activity",
		"runtime": "scripted",
		"description": "Word guessing game",
		"icon_url": "https://cdn.example.com/icon.png",
		"elf_url": "https://cdn.example.com/plugin.elf",
		"entry_point": "scenes/main.tscn",
		"bundle_size": 1024000,
		"bundle_hash": "sha256:abc123",
		"max_participants": 8,
		"max_spectators": -1,
		"max_file_size": 0,
		"version": "1.0.0",
		"permissions": ["voice_activity"],
		"lobby": true,
		"data_topics": ["game_state"],
		"signed": true,
		"signature": "ed25519:deadbeef",
		"canvas_size": [640, 480],
	}
	var m := AccordPluginManifest.from_dict(d)
	assert_eq(m.id, "codenames")
	assert_eq(m.name, "Codenames")
	assert_eq(m.type, "activity")
	assert_eq(m.runtime, "scripted")
	assert_eq(m.description, "Word guessing game")
	assert_eq(m.icon_url, "https://cdn.example.com/icon.png")
	assert_eq(m.elf_url, "https://cdn.example.com/plugin.elf")
	assert_eq(m.entry_point, "scenes/main.tscn")
	assert_eq(m.bundle_size, 1024000)
	assert_eq(m.bundle_hash, "sha256:abc123")
	assert_eq(m.max_participants, 8)
	assert_eq(m.max_spectators, -1)
	assert_eq(m.max_file_size, 0)
	assert_eq(m.version, "1.0.0")
	assert_eq(m.permissions, ["voice_activity"])
	assert_true(m.lobby)
	assert_eq(m.data_topics, ["game_state"])
	assert_true(m.signed)
	assert_eq(m.signature, "ed25519:deadbeef")
	assert_eq(m.canvas_size, [640, 480])


func test_from_dict_minimal() -> void:
	var m := AccordPluginManifest.from_dict({})
	assert_eq(m.id, "")
	assert_eq(m.name, "")
	assert_eq(m.type, "")
	assert_eq(m.runtime, "")
	assert_eq(m.description, "")
	assert_null(m.icon_url)
	assert_null(m.elf_url)
	assert_null(m.entry_point)
	assert_eq(m.bundle_size, 0)
	assert_eq(m.max_participants, 0)
	assert_false(m.lobby)
	assert_false(m.signed)
	assert_null(m.signature)
	assert_eq(m.canvas_size, [480, 360])


func test_to_dict_roundtrip() -> void:
	var original := {
		"id": "p1",
		"name": "Test",
		"type": "activity",
		"runtime": "native",
		"description": "A plugin",
		"bundle_size": 5000,
		"bundle_hash": "sha256:xyz",
		"max_participants": 4,
		"max_spectators": 0,
		"max_file_size": 1024,
		"version": "2.0.0",
		"permissions": [],
		"lobby": false,
		"data_topics": [],
		"signed": false,
		"canvas_size": [480, 360],
		"icon_url": "https://example.com/icon.png",
		"entry_point": "main.tscn",
	}
	var m := AccordPluginManifest.from_dict(original)
	var d := m.to_dict()
	assert_eq(d["id"], "p1")
	assert_eq(d["name"], "Test")
	assert_eq(d["runtime"], "native")
	assert_eq(d["version"], "2.0.0")
	assert_eq(d["icon_url"], "https://example.com/icon.png")
	assert_eq(d["entry_point"], "main.tscn")


func test_canvas_size_from_separate_fields() -> void:
	var d := {
		"id": "p1",
		"canvas_width": 800,
		"canvas_height": 600,
	}
	var m := AccordPluginManifest.from_dict(d)
	assert_eq(m.canvas_size, [800, 600])


func test_enums_defined() -> void:
	# Verify enum values exist and are accessible
	assert_eq(AccordPluginManifest.PluginRuntime.SCRIPTED, 0)
	assert_eq(AccordPluginManifest.PluginRuntime.NATIVE, 1)
	assert_eq(AccordPluginManifest.SessionState.LOBBY, 0)
	assert_eq(AccordPluginManifest.SessionState.RUNNING, 1)
	assert_eq(AccordPluginManifest.SessionState.ENDED, 2)
	assert_eq(AccordPluginManifest.ParticipantRole.SPECTATOR, 0)
	assert_eq(AccordPluginManifest.ParticipantRole.PLAYER, 1)
