extends PanelContainer

signal dm_selected(dm_id: String)

const DMChannelItemScene := preload("res://scenes/sidebar/direct/dm_channel_item.tscn")
const CreateGroupDMScene := preload("res://scenes/sidebar/direct/create_group_dm_dialog.tscn")
const FriendsListScene := preload("res://scenes/sidebar/direct/friends_list.tscn")

var dm_item_nodes: Dictionary = {}
var active_dm_id: String = ""
var _show_friends: bool = true

@onready var friends_btn: Button = $VBox/TabRow/FriendsBtn
@onready var messages_btn: Button = $VBox/TabRow/MessagesBtn
@onready var friends_list: VBoxContainer = $VBox/FriendsList
@onready var dm_panel: VBoxContainer = $VBox/DMPanel
@onready var search: LineEdit = $VBox/DMPanel/SearchContainer/Search
@onready var header_label: Label = $VBox/DMPanel/HeaderMargin/HeaderRow/HeaderLabel
@onready var new_group_btn: Button = $VBox/DMPanel/HeaderMargin/HeaderRow/NewGroupBtn
@onready var dm_vbox: VBoxContainer = $VBox/DMPanel/ScrollContainer/DMVBox

func _ready() -> void:
	add_to_group("themed")
	header_label.add_theme_font_size_override("font_size", 11)
	_apply_theme()
	new_group_btn.add_theme_font_size_override("font_size", 16)
	new_group_btn.pressed.connect(_on_new_group_pressed)
	search.text_changed.connect(_on_search_text_changed)
	friends_btn.pressed.connect(func(): _set_friends_mode(true))
	messages_btn.pressed.connect(func(): _set_friends_mode(false))
	AppState.dm_channels_updated.connect(_on_dm_channels_updated)
	AppState.user_updated.connect(_on_user_updated)
	_populate_dms()
	_set_friends_mode(true)

func _set_friends_mode(show_friends: bool) -> void:
	_show_friends = show_friends
	friends_list.visible = show_friends
	dm_panel.visible = not show_friends
	if show_friends:
		friends_btn.add_theme_color_override("font_color", ThemeManager.get_color("accent"))
		messages_btn.remove_theme_color_override("font_color")
	else:
		messages_btn.add_theme_color_override("font_color", ThemeManager.get_color("accent"))
		friends_btn.remove_theme_color_override("font_color")

func _apply_theme() -> void:
	var style: StyleBox = get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		style.bg_color = ThemeManager.get_color("panel_bg")
	header_label.add_theme_color_override("font_color", ThemeManager.get_color("text_muted"))

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

func _on_user_updated(user_id: String) -> void:
	# Refresh DM items that involve this user
	for dm in Client.dm_channels:
		var dm_user: Dictionary = dm.get("user", {})
		if dm_user.get("id", "") == user_id:
			var item = dm_item_nodes.get(dm["id"])
			if item != null and item.has_method("setup"):
				item.setup(dm)
			return
		# Also check group DM recipients
		if dm.get("is_group", false):
			for r in dm.get("recipients", []):
				if r.get("id", "") == user_id:
					var item = dm_item_nodes.get(dm["id"])
					if item != null and item.has_method("setup"):
						item.setup(dm)
					break

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
