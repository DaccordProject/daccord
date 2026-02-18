extends PanelContainer

@onready var avatar: ColorRect = $HBox/Avatar
@onready var display_name: Label = $HBox/Info/DisplayName
@onready var username: Label = $HBox/Info/Username
@onready var status_icon: ColorRect = $HBox/StatusIcon
@onready var menu_button: MenuButton = $HBox/MenuButton

func _ready() -> void:
	username.add_theme_font_size_override("font_size", 11)
	username.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643))
	# Setup menu
	var popup := menu_button.get_popup()
	popup.add_item("Online", 0)
	popup.add_item("Idle", 1)
	popup.add_item("Do Not Disturb", 2)
	popup.add_item("Invisible", 3)
	popup.add_separator()
	popup.add_item("About", 10)
	popup.add_item("Quit", 11)
	popup.id_pressed.connect(_on_menu_id_pressed)
	# Load current user
	var user: Dictionary = Client.current_user
	setup(user)
	# Refresh when a server connection completes (current_user is populated async)
	AppState.guilds_updated.connect(_on_guilds_updated)

func setup(user: Dictionary) -> void:
	display_name.text = user.get("display_name", "User")
	username.text = user.get("username", "user")
	avatar.set_avatar_color(user.get("color", Color(0.345, 0.396, 0.949)))

	var status: int = user.get("status", ClientModels.UserStatus.OFFLINE)
	match status:
		ClientModels.UserStatus.ONLINE:
			status_icon.color = Color(0.231, 0.647, 0.365)
		ClientModels.UserStatus.IDLE:
			status_icon.color = Color(0.98, 0.659, 0.157)
		ClientModels.UserStatus.DND:
			status_icon.color = Color(0.929, 0.259, 0.271)
		ClientModels.UserStatus.OFFLINE:
			status_icon.color = Color(0.58, 0.608, 0.643)

func _on_guilds_updated() -> void:
	setup(Client.current_user)

func _on_menu_id_pressed(id: int) -> void:
	match id:
		0:
			Client.current_user["status"] = ClientModels.UserStatus.ONLINE
			setup(Client.current_user)
		1:
			Client.current_user["status"] = ClientModels.UserStatus.IDLE
			setup(Client.current_user)
		2:
			Client.current_user["status"] = ClientModels.UserStatus.DND
			setup(Client.current_user)
		3:
			Client.current_user["status"] = ClientModels.UserStatus.OFFLINE
			setup(Client.current_user)
		11:
			get_tree().quit()
