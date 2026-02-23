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

func _fetch_servers() -> void:
	_status_label.text = "Loading servers..."
	_status_label.visible = true

	var master_url: String = Config.get_master_server_url()
	var url := master_url.trim_suffix("/") + "/api/v1/servers"

	var rest := AccordRest.new(master_url)
	add_child(rest)

	var http := HTTPRequest.new()
	add_child(http)
	http.request(url)
	var result: Array = await http.request_completed
	http.queue_free()
	rest.queue_free()

	var response_code: int = result[1]
	var body: PackedByteArray = result[3]

	if response_code == 0 or response_code >= 400:
		_status_label.text = "Could not reach master server"
		return

	var json := JSON.new()
	var parse_err := json.parse(body.get_string_from_utf8())
	if parse_err != OK:
		_status_label.text = "Failed to parse server list"
		return

	var data = json.data
	if data is Dictionary and data.has("data"):
		_all_servers = data["data"]
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
