extends PanelContainer

signal dm_selected(dm_id: String)

const DMChannelItemScene := preload("res://scenes/sidebar/direct/dm_channel_item.tscn")
const CreateGroupDMScene := preload("res://scenes/sidebar/direct/create_group_dm_dialog.tscn")

var dm_item_nodes: Dictionary = {}
var active_dm_id: String = ""

@onready var search: LineEdit = $VBox/SearchContainer/Search
@onready var header_label: Label = $VBox/HeaderMargin/HeaderRow/HeaderLabel
@onready var new_group_btn: Button = $VBox/HeaderMargin/HeaderRow/NewGroupBtn
@onready var dm_vbox: VBoxContainer = $VBox/ScrollContainer/DMVBox

func _ready() -> void:
	header_label.add_theme_font_size_override("font_size", 11)
	header_label.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643))
	new_group_btn.add_theme_font_size_override("font_size", 16)
	new_group_btn.pressed.connect(_on_new_group_pressed)
	search.text_changed.connect(_on_search_text_changed)
	AppState.dm_channels_updated.connect(_on_dm_channels_updated)
	_populate_dms()

func _populate_dms() -> void:
	for child in dm_vbox.get_children():
		child.queue_free()
	dm_item_nodes.clear()

	for dm in Client.dm_channels:
		var item: Button = DMChannelItemScene.instantiate()
		dm_vbox.add_child(item)
		item.setup(dm)
		dm_item_nodes[dm["id"]] = item
		item.dm_pressed.connect(func(id: String):
			_set_active_dm(id)
			dm_selected.emit(id)
		)
		item.dm_closed.connect(func(id: String):
			Client.close_dm(id)
		)

func _set_active_dm(dm_id: String) -> void:
	if active_dm_id != "" and dm_item_nodes.has(active_dm_id):
		dm_item_nodes[active_dm_id].set_active(false)
	active_dm_id = dm_id
	if dm_item_nodes.has(dm_id):
		dm_item_nodes[dm_id].set_active(true)

func _on_dm_channels_updated() -> void:
	_populate_dms()

func _on_new_group_pressed() -> void:
	var dialog := CreateGroupDMScene.instantiate()
	get_tree().root.add_child(dialog)

func _on_search_text_changed(new_text: String) -> void:
	var query := new_text.strip_edges().to_lower()
	for dm in Client.dm_channels:
		var item = dm_item_nodes.get(dm["id"])
		if item == null:
			continue
		if query.is_empty():
			item.visible = true
		else:
			var user: Dictionary = dm.get("user", {})
			var display_name: String = user.get(
				"display_name", ""
			).to_lower()
			var username: String = user.get(
				"username", ""
			).to_lower()
			var matched: bool = display_name.contains(query) \
				or username.contains(query)
			# For group DMs, also search custom name and
			# individual recipient names/usernames
			if not matched and dm.get("is_group", false):
				var dm_name: String = dm.get(
					"name", ""
				).to_lower()
				if not dm_name.is_empty() \
						and dm_name.contains(query):
					matched = true
				if not matched:
					for r in dm.get("recipients", []):
						var rdn: String = r.get(
							"display_name", ""
						).to_lower()
						var run: String = r.get(
							"username", ""
						).to_lower()
						if rdn.contains(query) \
								or run.contains(query):
							matched = true
							break
			item.visible = matched
