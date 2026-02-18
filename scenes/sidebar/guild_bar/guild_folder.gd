extends VBoxContainer

signal guild_pressed(guild_id: String)

const GuildIconScene := preload("res://scenes/sidebar/guild_bar/guild_icon.tscn")

var folder_name: String = ""
var is_expanded: bool = false
var guild_icons: Array = []

@onready var folder_button: Button = $FolderButton
@onready var mini_grid: GridContainer = $FolderButton/MiniGrid
@onready var guild_list: VBoxContainer = $GuildList

func _ready() -> void:
	folder_button.pressed.connect(_toggle_expanded)
	folder_button.tooltip_text = folder_name
	# Style folder button
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.212, 0.224, 0.247)
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	folder_button.add_theme_stylebox_override("normal", style)

func setup(p_name: String, guilds: Array, folder_color: Color = Color(0.212, 0.224, 0.247)) -> void:
	folder_name = p_name
	if folder_button:
		folder_button.tooltip_text = p_name
		# Apply folder color (darkened)
		var style: StyleBoxFlat = folder_button.get_theme_stylebox("normal").duplicate()
		style.bg_color = folder_color.darkened(0.6)
		folder_button.add_theme_stylebox_override("normal", style)

	# Create mini grid preview (up to 4 tiny color squares)
	for child in mini_grid.get_children():
		child.queue_free()
	for i in min(guilds.size(), 4):
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.color = guilds[i].get("icon_color", Color.GRAY)
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mini_grid.add_child(swatch)

	# Create full guild icons for expanded view
	for child in guild_list.get_children():
		child.queue_free()
	for g in guilds:
		var icon: HBoxContainer = GuildIconScene.instantiate()
		guild_list.add_child(icon)
		icon.setup(g)
		icon.guild_pressed.connect(func(id: String): guild_pressed.emit(id))
		guild_icons.append(icon)

func _toggle_expanded() -> void:
	is_expanded = !is_expanded
	mini_grid.visible = !is_expanded
	guild_list.visible = is_expanded
