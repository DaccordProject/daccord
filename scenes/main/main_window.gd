extends Control

const DRAWER_WIDTH := 308

var tabs: Array[Dictionary] = []
var _drawer_tween: Tween
var _sidebar_in_drawer: bool = false

@onready var layout_hbox: HBoxContainer = $LayoutHBox
@onready var sidebar: HBoxContainer = $LayoutHBox/Sidebar
@onready var content_area: VBoxContainer = $LayoutHBox/ContentArea
@onready var hamburger_button: Button = $LayoutHBox/ContentArea/ContentHeader/HamburgerButton
@onready var sidebar_toggle: Button = $LayoutHBox/ContentArea/ContentHeader/SidebarToggle
@onready var tab_bar: TabBar = $LayoutHBox/ContentArea/ContentHeader/TabBar
@onready var member_toggle: Button = $LayoutHBox/ContentArea/ContentHeader/MemberListToggle
@onready var topic_bar: Label = $LayoutHBox/ContentArea/TopicBar
@onready var content_body: HBoxContainer = $LayoutHBox/ContentArea/ContentBody
@onready var message_view: PanelContainer = $LayoutHBox/ContentArea/ContentBody/MessageView
@onready var member_list: PanelContainer = $LayoutHBox/ContentArea/ContentBody/MemberList
@onready var drawer_backdrop: ColorRect = $DrawerBackdrop
@onready var drawer_container: Control = $DrawerContainer

func _ready() -> void:
	AppState.channel_selected.connect(_on_channel_selected)
	AppState.sidebar_drawer_toggled.connect(_on_sidebar_drawer_toggled)
	AppState.layout_mode_changed.connect(_on_layout_mode_changed)
	tab_bar.tab_changed.connect(_on_tab_changed)
	tab_bar.tab_close_pressed.connect(_on_tab_close)
	hamburger_button.pressed.connect(_on_hamburger_pressed)
	sidebar_toggle.pressed.connect(_on_sidebar_toggle_pressed)
	member_toggle.pressed.connect(_on_member_toggle_pressed)
	AppState.channel_panel_toggled.connect(_on_channel_panel_toggled)
	AppState.member_list_toggled.connect(_on_member_list_toggled)
	AppState.dm_mode_entered.connect(_on_dm_mode_entered)
	AppState.guild_selected.connect(_on_guild_selected)
	drawer_backdrop.gui_input.connect(_on_backdrop_input)
	get_viewport().size_changed.connect(_on_viewport_resized)
	# Style topic bar
	topic_bar.add_theme_font_size_override("font_size", 12)
	topic_bar.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643))

	_update_tab_visibility()

	# Apply initial layout
	_on_viewport_resized()

func _on_channel_selected(channel_id: String) -> void:
	# Find channel name and topic
	var channel_name := channel_id
	var topic := ""
	for ch in Client.channels:
		if ch["id"] == channel_id:
			channel_name = ch.get("name", channel_id)
			topic = ch.get("topic", "")
			break
	for dm in Client.dm_channels:
		if dm["id"] == channel_id:
			var user: Dictionary = dm.get("user", {})
			channel_name = user.get("display_name", channel_id)
			break

	# Update window title
	if AppState.is_dm_mode:
		get_window().title = "daccord - " + channel_name
	else:
		get_window().title = "daccord - #" + channel_name

	# Update topic bar
	if topic != "":
		topic_bar.text = topic
		topic_bar.visible = true
	else:
		topic_bar.visible = false

	# Check if tab already exists
	for i in tabs.size():
		if tabs[i]["channel_id"] == channel_id:
			tab_bar.current_tab = i
			return

	_add_tab(channel_name, channel_id)

func _add_tab(tab_name: String, channel_id: String) -> void:
	tabs.append({"name": tab_name, "channel_id": channel_id})
	tab_bar.add_tab(tab_name)
	tab_bar.current_tab = tabs.size() - 1
	_update_tab_visibility()

func _on_tab_changed(tab_index: int) -> void:
	if tab_index >= 0 and tab_index < tabs.size():
		var channel_id: String = tabs[tab_index]["channel_id"]
		AppState.select_channel(channel_id)

func _on_tab_close(tab_index: int) -> void:
	if tabs.size() <= 1:
		return
	tabs.remove_at(tab_index)
	tab_bar.remove_tab(tab_index)
	if tab_bar.current_tab >= 0 and tab_bar.current_tab < tabs.size():
		var channel_id: String = tabs[tab_bar.current_tab]["channel_id"]
		AppState.select_channel(channel_id)
	_update_tab_visibility()

func _update_tab_visibility() -> void:
	# Hide tab bar when only one tab
	tab_bar.visible = tabs.size() > 1

func _on_viewport_resized() -> void:
	var vp_width := get_viewport().get_visible_rect().size.x
	AppState.update_layout_mode(vp_width)

func _on_layout_mode_changed(mode: AppState.LayoutMode) -> void:
	match mode:
		AppState.LayoutMode.FULL:
			_move_sidebar_to_layout()
			sidebar.visible = true
			sidebar.set_channel_panel_visible(AppState.channel_panel_visible)
			hamburger_button.visible = false
			sidebar_toggle.visible = true
			_close_drawer_immediate()
			_update_member_list_visibility()
		AppState.LayoutMode.MEDIUM:
			_move_sidebar_to_layout()
			sidebar.visible = true
			sidebar.set_channel_panel_visible(AppState.channel_panel_visible)
			hamburger_button.visible = false
			sidebar_toggle.visible = true
			_close_drawer_immediate()
			AppState.member_list_visible = false
			_update_member_list_visibility()
		AppState.LayoutMode.COMPACT:
			_move_sidebar_to_drawer()
			sidebar.set_channel_panel_visible(true)
			hamburger_button.visible = true
			sidebar_toggle.visible = false
			_close_drawer_immediate()
			member_toggle.visible = false
			member_list.visible = false

func _on_sidebar_toggle_pressed() -> void:
	AppState.toggle_channel_panel()

func _on_channel_panel_toggled(is_visible: bool) -> void:
	if AppState.current_layout_mode != AppState.LayoutMode.COMPACT:
		sidebar.set_channel_panel_visible(is_visible)

func _on_member_toggle_pressed() -> void:
	AppState.toggle_member_list()

func _on_member_list_toggled(_is_visible: bool) -> void:
	_update_member_list_visibility()

func _on_dm_mode_entered() -> void:
	member_toggle.visible = false
	member_list.visible = false

func _on_guild_selected(_guild_id: String) -> void:
	_update_member_list_visibility()

func _update_member_list_visibility() -> void:
	if AppState.is_dm_mode:
		member_toggle.visible = false
		member_list.visible = false
		return
	match AppState.current_layout_mode:
		AppState.LayoutMode.FULL:
			member_toggle.visible = true
			member_list.visible = AppState.member_list_visible
		AppState.LayoutMode.MEDIUM:
			member_toggle.visible = true
			member_list.visible = AppState.member_list_visible
		AppState.LayoutMode.COMPACT:
			member_toggle.visible = false
			member_list.visible = false

func _move_sidebar_to_layout() -> void:
	if not _sidebar_in_drawer:
		return
	_sidebar_in_drawer = false
	drawer_container.remove_child(sidebar)
	layout_hbox.add_child(sidebar)
	layout_hbox.move_child(sidebar, 0)

func _move_sidebar_to_drawer() -> void:
	if _sidebar_in_drawer:
		return
	_sidebar_in_drawer = true
	layout_hbox.remove_child(sidebar)
	drawer_container.add_child(sidebar)
	# Position sidebar inside drawer
	sidebar.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	sidebar.offset_right = DRAWER_WIDTH

func _on_hamburger_pressed() -> void:
	AppState.toggle_sidebar_drawer()

func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		AppState.close_sidebar_drawer()
	elif event is InputEventScreenTouch and event.pressed:
		AppState.close_sidebar_drawer()

func _on_sidebar_drawer_toggled(is_open: bool) -> void:
	if is_open:
		_open_drawer()
	else:
		_close_drawer()

func _open_drawer() -> void:
	if _drawer_tween:
		_drawer_tween.kill()
	drawer_backdrop.visible = true
	drawer_container.visible = true
	sidebar.visible = true
	# Animate: slide in from left
	sidebar.position.x = -DRAWER_WIDTH
	drawer_backdrop.modulate.a = 0.0
	_drawer_tween = create_tween().set_parallel(true)
	_drawer_tween.tween_property(
		sidebar, "position:x", 0.0, 0.2
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_drawer_tween.tween_property(drawer_backdrop, "modulate:a", 1.0, 0.2)

func _close_drawer() -> void:
	if _drawer_tween:
		_drawer_tween.kill()
	_drawer_tween = create_tween().set_parallel(true)
	_drawer_tween.tween_property(
		sidebar, "position:x", float(-DRAWER_WIDTH), 0.2
	).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_drawer_tween.tween_property(drawer_backdrop, "modulate:a", 0.0, 0.2)
	_drawer_tween.chain().tween_callback(_hide_drawer_nodes)

func _close_drawer_immediate() -> void:
	if _drawer_tween:
		_drawer_tween.kill()
	_hide_drawer_nodes()

func _hide_drawer_nodes() -> void:
	drawer_backdrop.visible = false
	drawer_container.visible = false
	AppState.sidebar_drawer_open = false
