class_name AccordPluginManifest
extends RefCounted

## Plugin manifest describing a server-installed plugin.

enum PluginRuntime { SCRIPTED, NATIVE }
enum SessionState { LOBBY, RUNNING, ENDED }
enum ParticipantRole { SPECTATOR, PLAYER }

var id: String = ""
var name: String = ""
var type: String = ""              # "activity", "bot", "theme", "command"
var runtime: String = ""           # "scripted" or "native"
var description: String = ""
var icon_url = null
var elf_url = null
var entry_point = null             # scene path within bundle (native plugins)
var bundle_size: int = 0
var bundle_hash: String = ""       # "sha256:<hex>" (native plugins)
var max_participants: int = 0      # 0 = unlimited
var max_spectators: int = 0        # 0 = unlimited; -1 = no spectators
var max_file_size: int = 0         # max user-supplied file size in bytes (0 = no file sharing)
var version: String = ""
var permissions: Array = []
var lobby: bool = false
var data_topics: Array = []
var signed: bool = false
var signature = null
var canvas_size: Array = [480, 360] # [width, height] for scripted plugins


static func from_dict(d: Dictionary) -> AccordPluginManifest:
	var m := AccordPluginManifest.new()
	m.id = str(d.get("id", ""))
	m.name = d.get("name", "")
	m.type = d.get("type", "")
	m.runtime = d.get("runtime", "")
	m.description = d.get("description", "")
	var raw_icon = d.get("icon_url", null)
	m.icon_url = str(raw_icon) if raw_icon != null else null
	var raw_elf = d.get("elf_url", null)
	m.elf_url = str(raw_elf) if raw_elf != null else null
	var raw_entry = d.get("entry_point", null)
	m.entry_point = str(raw_entry) if raw_entry != null else null
	m.bundle_size = int(d.get("bundle_size", 0))
	m.bundle_hash = d.get("bundle_hash", "")
	m.max_participants = int(d.get("max_participants", 0))
	m.max_spectators = int(d.get("max_spectators", 0))
	m.max_file_size = int(d.get("max_file_size", 0))
	m.version = d.get("version", "")
	m.permissions = d.get("permissions", [])
	m.lobby = d.get("lobby", false)
	m.data_topics = d.get("data_topics", [])
	m.signed = d.get("signed", false)
	var raw_sig = d.get("signature", null)
	m.signature = str(raw_sig) if raw_sig != null else null
	var raw_canvas = d.get("canvas_size", null)
	if raw_canvas is Array and raw_canvas.size() >= 2:
		m.canvas_size = [int(raw_canvas[0]), int(raw_canvas[1])]
	elif d.has("canvas_width") and d.has("canvas_height"):
		m.canvas_size = [int(d["canvas_width"]), int(d["canvas_height"])]
	return m


func to_dict() -> Dictionary:
	var d := {
		"id": id,
		"name": name,
		"type": type,
		"runtime": runtime,
		"description": description,
		"bundle_size": bundle_size,
		"bundle_hash": bundle_hash,
		"max_participants": max_participants,
		"max_spectators": max_spectators,
		"max_file_size": max_file_size,
		"version": version,
		"permissions": permissions,
		"lobby": lobby,
		"data_topics": data_topics,
		"signed": signed,
		"canvas_size": canvas_size,
	}
	if icon_url != null:
		d["icon_url"] = icon_url
	if elf_url != null:
		d["elf_url"] = elf_url
	if entry_point != null:
		d["entry_point"] = entry_point
	if signature != null:
		d["signature"] = signature
	return d
