extends VBoxContainer

signal channel_pressed(channel_id: String)

const CHEVRON_DOWN := preload("res://theme/icons/chevron_down.svg")
const CHEVRON_RIGHT := preload("res://theme/icons/chevron_right.svg")
const ChannelItemScene := preload("res://scenes/sidebar/channels/channel_item.tscn")

var is_collapsed: bool = false

@onready var header: Button = $Header
@onready var chevron: TextureRect = $Header/HBox/Chevron
@onready var category_name: Label = $Header/HBox/CategoryName
@onready var channel_container: VBoxContainer = $ChannelContainer

func _ready() -> void:
	header.pressed.connect(_toggle_collapsed)
	chevron.texture = CHEVRON_DOWN
	chevron.modulate = Color(0.58, 0.608, 0.643)
	category_name.add_theme_font_size_override("font_size", 11)
	category_name.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643))

func setup(data: Dictionary, child_channels: Array) -> void:
	category_name.text = data.get("name", "").to_upper()

	for ch in child_channels:
		var item: Button = ChannelItemScene.instantiate()
		channel_container.add_child(item)
		item.setup(ch)
		item.channel_pressed.connect(func(id: String): channel_pressed.emit(id))

func _toggle_collapsed() -> void:
	is_collapsed = !is_collapsed
	channel_container.visible = !is_collapsed
	chevron.texture = CHEVRON_RIGHT if is_collapsed else CHEVRON_DOWN

func get_channel_items() -> Array:
	var items := []
	for child in channel_container.get_children():
		items.append(child)
	return items
