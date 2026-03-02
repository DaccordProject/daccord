extends VBoxContainer

signal join_pressed(server_url: String, space_id: String)

const ServerCardScene := preload("res://scenes/sidebar/guild_bar/server_card.tscn")

var _all_servers: Array = []

@onready var _search_input: LineEdit = $SearchInput
@onready var _scroll: ScrollContainer = $ScrollContainer
@onready var _server_list: VBoxContainer = $ScrollContainer/ServerList
@onready var _status_label: Label = $StatusLabel

func _ready() -> void:
	_search_input.text_changed.connect(_on_search_changed)
	_fetch_servers()

func _fetch_servers(query: String = "") -> void:
	_status_label.text = "Loading servers..."
	_status_label.visible = true

	var master_url: String = Config.get_master_server_url()
	var rest := AccordRest.new(master_url)
	add_child(rest)

	var api := DirectoryApi.new(rest)
	var result: RestResult = await api.browse(query)
	rest.queue_free()

	if not result.ok:
		var msg: String = result.error.message if result.error else "Could not reach master server"
		_status_label.text = msg
		return

	var data = result.data
	if data is Dictionary and data.has("spaces"):
		_all_servers = data["spaces"]
	elif data is Dictionary and data.has("data"):
		_all_servers = data["data"]
	elif data is Array:
		_all_servers = data
	else:
		_all_servers = []

	if _all_servers.is_empty():
		_status_label.text = "No servers found"
		return

	_status_label.visible = false
	_populate_servers(_all_servers)

func _populate_servers(servers: Array) -> void:
	for child in _server_list.get_children():
		child.queue_free()

	for server in servers:
		var card: VBoxContainer = ServerCardScene.instantiate()
		_server_list.add_child(card)
		card.setup(server)
		card.join_pressed.connect(func(s_url: String, s_id: String): join_pressed.emit(s_url, s_id))

func _on_search_changed(query: String) -> void:
	var q := query.strip_edges().to_lower()
	if q.is_empty():
		_populate_servers(_all_servers)
		return

	var filtered: Array = []
	for server in _all_servers:
		var name: String = server.get("name", "").to_lower()
		if q in name:
			filtered.append(server)
			continue
		# Also search space names
		var spaces: Array = server.get("spaces", [])
		var matched := false
		for space in spaces:
			var sname: String = space.get("name", "").to_lower()
			if q in sname:
				matched = true
				break
		if matched:
			filtered.append(server)

	_populate_servers(filtered)
