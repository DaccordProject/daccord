extends AcceptDialog

var _server_checkboxes: Dictionary = {} # guild_id -> CheckBox

@onready var suppress_check: CheckBox = $VBox/SuppressCheck
@onready var servers_container: VBoxContainer = $VBox/ServersContainer

func _ready() -> void:
	title = "Notification Settings"
	ok_button_text = "Apply"

	suppress_check.button_pressed = Config.get_suppress_everyone()

	for guild in Client.guilds:
		var guild_id: String = guild.get("id", "")
		var guild_name: String = guild.get("name", guild_id)
		var cb := CheckBox.new()
		cb.text = "Mute " + guild_name
		cb.button_pressed = Config.is_server_muted(guild_id)
		servers_container.add_child(cb)
		_server_checkboxes[guild_id] = cb

	confirmed.connect(_on_confirmed)

func _on_confirmed() -> void:
	Config.set_suppress_everyone(suppress_check.button_pressed)
	for guild_id in _server_checkboxes:
		var cb: CheckBox = _server_checkboxes[guild_id]
		Config.set_server_muted(guild_id, cb.button_pressed)
