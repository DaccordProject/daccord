extends Control

const PANEL_HANDLE_WIDTH := 6.0
const MESSAGE_VIEW_MIN := 300.0
const PANEL_MIN_THREAD := 240.0
const PANEL_MIN_MEMBER := 180.0
const PANEL_MIN_SEARCH := 240.0
const DrawerGestures := preload("res://scenes/main/drawer_gestures.gd")
const PanelResizeHandle := preload("res://scenes/main/panel_resize_handle.gd")
const AvatarScript := preload("res://scenes/common/avatar.gd")
const ProfileCardScene := preload(
	"res://scenes/user/profile_card.tscn"
)
const WelcomeScreenScene := preload(
	"res://scenes/main/welcome_screen.tscn"
)
const ConnectingOverlayScene := preload(
	"res://scenes/main/connecting_overlay.tscn"
)
const ImageLightboxScene := preload(
	"res://scenes/messages/image_lightbox.tscn"
)

var tabs: Array[Dictionary] = []

var _guild_icon_cache: Dictionary = {}
var _drawer: MainWindowDrawer
var _active_profile_card: PanelContainer = null
var _welcome_screen: Control = null
var _member_list_before_medium: bool = true
var _gestures: RefCounted
var _thread_handle: Control
var _member_handle: Control
var _search_handle: Control
var _clamping_panels: bool = false

@onready var layout_hbox: HBoxContainer = $LayoutHBox
@onready var sidebar: HBoxContainer = $LayoutHBox/Sidebar
@onready var content_area: VBoxContainer = $LayoutHBox/ContentArea
@onready var hamburger_button: Button = $LayoutHBox/ContentArea/ContentHeader/HamburgerButton
@onready var sidebar_toggle: Button = $LayoutHBox/ContentArea/ContentHeader/SidebarToggle
@onready var tab_bar: TabBar = $LayoutHBox/ContentArea/ContentHeader/TabBar
@onready var search_toggle: Button = $LayoutHBox/ContentArea/ContentHeader/SearchToggle
@onready var member_toggle: Button = $LayoutHBox/ContentArea/ContentHeader/MemberListToggle
@onready var topic_bar: Label = $LayoutHBox/ContentArea/TopicBar
@onready var content_body: HBoxContainer = $LayoutHBox/ContentArea/ContentBody
@onready var message_view: PanelContainer = $LayoutHBox/ContentArea/ContentBody/MessageView
@onready var thread_panel: PanelContainer = $LayoutHBox/ContentArea/ContentBody/ThreadPanel
@onready var member_list: PanelContainer = $LayoutHBox/ContentArea/ContentBody/MemberList
@onready var search_panel: PanelContainer = $LayoutHBox/ContentArea/ContentBody/SearchPanel
@onready var drawer_backdrop: ColorRect = $DrawerBackdrop
@onready var drawer_container: Control = $DrawerContainer

func _ready() -> void:
	_drawer = MainWindowDrawer.new(
		self, sidebar, drawer_container, drawer_backdrop, layout_hbox
	)
	_apply_ui_scale()
	_gestures = DrawerGestures.new(self)
	AppState.channel_selected.connect(_on_channel_selected)
	AppState.sidebar_drawer_toggled.connect(_drawer.on_sidebar_drawer_toggled)
	AppState.layout_mode_changed.connect(_on_layout_mode_changed)
	tab_bar.tab_changed.connect(_on_tab_changed)
	tab_bar.tab_close_pressed.connect(_on_tab_close)
	tab_bar.active_tab_rearranged.connect(_on_tab_rearranged)
	hamburger_button.pressed.connect(_on_hamburger_pressed)
	sidebar_toggle.pressed.connect(_on_sidebar_toggle_pressed)
	member_toggle.pressed.connect(_on_member_toggle_pressed)
	search_toggle.pressed.connect(_on_search_toggle_pressed)
	AppState.channel_panel_toggled.connect(_on_channel_panel_toggled)
	AppState.member_list_toggled.connect(_on_member_list_toggled)
	AppState.search_toggled.connect(_on_search_toggled)
	AppState.dm_mode_entered.connect(_on_dm_mode_entered)
	AppState.guild_selected.connect(_on_guild_selected)
	AppState.reauth_needed.connect(_on_reauth_needed)
	AppState.profile_switched.connect(_on_profile_switched)
	AppState.server_removed.connect(_on_server_removed)
	drawer_backdrop.gui_input.connect(_on_backdrop_input)
	get_viewport().size_changed.connect(_on_viewport_resized)
	AppState.thread_opened.connect(_on_thread_opened)
	AppState.thread_closed.connect(_on_thread_closed)
	AppState.profile_card_requested.connect(_on_profile_card_requested)
	AppState.image_lightbox_requested.connect(_on_image_lightbox_requested)
	AppState.update_download_complete.connect(_on_update_download_complete)
	AppState.voice_error.connect(_on_voice_error)
	# Style topic bar
	topic_bar.add_theme_font_size_override("font_size", 12)
	topic_bar.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643))

	# Create resize handles for side panels
	_thread_handle = PanelResizeHandle.new(
		thread_panel, 240.0, 0.0, 340.0, 0.8,
	)
	content_body.add_child(_thread_handle)
	content_body.move_child(_thread_handle, thread_panel.get_index())

	_member_handle = PanelResizeHandle.new(
		member_list, 180.0, 400.0, 240.0,
	)
	content_body.add_child(_member_handle)
	content_body.move_child(_member_handle, member_list.get_index())

	_search_handle = PanelResizeHandle.new(
		search_panel, 240.0, 500.0, 340.0,
	)
	content_body.add_child(_search_handle)
	content_body.move_child(_search_handle, search_panel.get_index())

	_sync_handle_visibility()
	content_body.resized.connect(_clamp_panel_widths)

	_update_tab_visibility()

	# Apply initial layout
	_on_viewport_resized()

	# Error reporting consent (first launch only)
	if not Config.has_error_reporting_preference():
		call_deferred("_show_consent_dialog")

	# Crash recovery toast
	if Config.get_error_reporting_enabled() and ErrorReporting._initialized:
		var last_id_value = SentrySDK.get_last_event_id()
		var last_id: String = last_id_value if last_id_value != null else ""
		if not last_id.is_empty():
			call_deferred("_show_crash_toast")

	# Welcome screen for first launch (no servers configured)
	if not Config.has_servers():
		_show_welcome_screen()
	elif int(Client.mode) == Client.Mode.CONNECTING:
		_show_connecting_overlay()

func _apply_ui_scale() -> void:
	var scale: float = Config.get_ui_scale()
	if scale <= 0.0:
		scale = _auto_ui_scale()
	if scale <= 1.0:
		return
	get_window().content_scale_factor = scale

func _auto_ui_scale() -> float:
	var allow_hidpi: bool = ProjectSettings.get_setting(
		"display/window/dpi/allow_hidpi"
	)
	if not allow_hidpi:
		return 1.0
	var screen: int = DisplayServer.window_get_current_screen(
		DisplayServer.MAIN_WINDOW_ID
	)
	var screen_scale: float = DisplayServer.screen_get_scale(screen)
	if screen_scale <= 1.0:
		return 1.0
	return clampf(screen_scale, 1.0, 2.0)

func _input(event: InputEvent) -> void:
	if AppState.current_layout_mode != AppState.LayoutMode.COMPACT:
		return
	_gestures.handle_input(event)

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

	# Look up guild for this channel
	var guild_id: String = Client._channel_to_guild.get(channel_id, "")

	# Check if tab already exists
	for i in tabs.size():
		if tabs[i]["channel_id"] == channel_id:
			tab_bar.current_tab = i
			return

	_add_tab(channel_name, channel_id, guild_id)

func _add_tab(tab_name: String, channel_id: String, guild_id: String) -> void:
	tabs.append({"name": tab_name, "channel_id": channel_id, "guild_id": guild_id})
	tab_bar.add_tab(tab_name)
	tab_bar.current_tab = tabs.size() - 1
	_update_tab_visibility()
	_update_tab_icons()

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
	_update_tab_icons()

func _on_tab_rearranged(idx_to: int) -> void:
	var active_channel_id: String = AppState.current_channel_id
	var idx_from: int = -1
	for i in tabs.size():
		if tabs[i]["channel_id"] == active_channel_id:
			idx_from = i
			break
	if idx_from == -1 or idx_from == idx_to:
		return
	var tab_data: Dictionary = tabs[idx_from]
	tabs.remove_at(idx_from)
	tabs.insert(idx_to, tab_data)
	_update_tab_icons()

func _on_server_removed(guild_id: String) -> void:
	# Remove tabs belonging to the disconnected server
	var i: int = tabs.size() - 1
	while i >= 0:
		if tabs[i].get("guild_id", "") == guild_id:
			tabs.remove_at(i)
			tab_bar.remove_tab(i)
		i -= 1
	if tabs.is_empty():
		return
	# Ensure a valid tab is selected
	var current: int = clampi(tab_bar.current_tab, 0, tabs.size() - 1)
	tab_bar.current_tab = current
	AppState.select_channel(tabs[current]["channel_id"])
	_update_tab_visibility()
	_update_tab_icons()

func _update_tab_visibility() -> void:
	# Hide tab bar when only one tab
	tab_bar.visible = tabs.size() > 1

func _update_tab_icons() -> void:
	# Count name occurrences
	var name_count: Dictionary = {}
	for tab in tabs:
		var n: String = tab["name"]
		name_count[n] = name_count.get(n, 0) + 1

	for i in tabs.size():
		if name_count[tabs[i]["name"]] > 1:
			_set_guild_icon_for_tab(i)
		else:
			tab_bar.set_tab_icon(i, null)

func _set_guild_icon_for_tab(tab_index: int) -> void:
	var guild_id: String = tabs[tab_index].get("guild_id", "")
	if guild_id.is_empty():
		tab_bar.set_tab_icon(tab_index, null)
		return

	# Already cached locally
	if _guild_icon_cache.has(guild_id):
		tab_bar.set_tab_icon(tab_index, _guild_icon_cache[guild_id])
		return

	var guild: Dictionary = Client.get_guild_by_id(guild_id)
	if guild.is_empty():
		tab_bar.set_tab_icon(tab_index, null)
		return

	var icon_url_value = guild.get("icon", "")
	var icon_url: String = icon_url_value if icon_url_value != null else ""
	if icon_url.is_empty():
		# Fallback: solid-color swatch
		var tex: ImageTexture = _create_color_swatch(
			guild.get("icon_color", Color.GRAY)
		)
		_guild_icon_cache[guild_id] = tex
		tab_bar.set_tab_icon(tab_index, tex)
		return

	# Check avatar's shared cache
	if AvatarScript._image_cache.has(icon_url):
		var tex: ImageTexture = AvatarScript._image_cache[icon_url]
		_guild_icon_cache[guild_id] = tex
		tab_bar.set_tab_icon(tab_index, tex)
		return

	# Fetch asynchronously
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(
		_on_tab_icon_loaded.bind(guild_id, http)
	)
	http.request(icon_url)

func _on_tab_icon_loaded(
	result: int, response_code: int,
	_headers: PackedStringArray, body: PackedByteArray,
	guild_id: String, http: HTTPRequest,
) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var image := Image.new()
	var err := image.load_png_from_buffer(body)
	if err != OK:
		err = image.load_jpg_from_buffer(body)
	if err != OK:
		err = image.load_webp_from_buffer(body)
	if err != OK:
		return
	image.resize(16, 16)
	var tex := ImageTexture.create_from_image(image)
	_guild_icon_cache[guild_id] = tex
	# Apply to any tabs that need this guild's icon
	_update_tab_icons()

func _create_color_swatch(c: Color, px: int = 16) -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)

func _on_viewport_resized() -> void:
	var vp_size := get_viewport().get_visible_rect().size
	AppState.update_layout_mode(vp_size.x, vp_size.y)
	# Recalculate drawer width if sidebar is in drawer and open
	if _drawer.is_in_drawer() and AppState.sidebar_drawer_open:
		sidebar.offset_right = _drawer.get_drawer_width()

func _on_layout_mode_changed(mode: AppState.LayoutMode) -> void:
	match mode:
		AppState.LayoutMode.FULL:
			_drawer.move_sidebar_to_layout()
			sidebar.visible = true
			sidebar.set_channel_panel_visible_immediate(AppState.channel_panel_visible)
			hamburger_button.visible = false
			sidebar_toggle.visible = true
			_drawer.close_drawer_immediate()
			AppState.member_list_visible = _member_list_before_medium
			message_view.visible = true
			_update_member_list_visibility()
			_update_search_visibility()
			_sync_handle_visibility()
		AppState.LayoutMode.MEDIUM:
			_drawer.move_sidebar_to_layout()
			sidebar.visible = true
			sidebar.set_channel_panel_visible_immediate(AppState.channel_panel_visible)
			hamburger_button.visible = false
			sidebar_toggle.visible = true
			_drawer.close_drawer_immediate()
			_member_list_before_medium = AppState.member_list_visible
			AppState.member_list_visible = false
			message_view.visible = true
			_update_member_list_visibility()
			_update_search_visibility()
			_sync_handle_visibility()
		AppState.LayoutMode.COMPACT:
			_drawer.move_sidebar_to_drawer()
			sidebar.set_channel_panel_visible_immediate(true)
			hamburger_button.visible = true
			sidebar_toggle.visible = false
			_drawer.close_drawer_immediate()
			member_toggle.visible = false
			member_list.visible = false
			search_toggle.visible = false
			search_panel.visible = false
			AppState.close_search()
			_sync_handle_visibility()
			# In compact mode, thread panel replaces message view
			if AppState.thread_panel_visible:
				message_view.visible = false
			else:
				message_view.visible = true

func _sync_handle_visibility() -> void:
	var is_compact: bool = (
		AppState.current_layout_mode == AppState.LayoutMode.COMPACT
	)
	_thread_handle.visible = thread_panel.visible and not is_compact
	_member_handle.visible = member_list.visible and not is_compact
	_search_handle.visible = search_panel.visible and not is_compact
	_clamp_panel_widths()

func _clamp_panel_widths() -> void:
	if _clamping_panels:
		return
	_clamping_panels = true

	var available: float = content_body.size.x
	# Reserve space for visible handles
	var reserved: float = MESSAGE_VIEW_MIN
	if _thread_handle.visible:
		reserved += PANEL_HANDLE_WIDTH
	if _member_handle.visible:
		reserved += PANEL_HANDLE_WIDTH
	if _search_handle.visible:
		reserved += PANEL_HANDLE_WIDTH

	var budget: float = available - reserved
	if budget <= 0.0:
		_clamping_panels = false
		return

	# Collect visible panels and their hard minimums
	var panels: Array[Array] = []
	if thread_panel.visible:
		panels.append([thread_panel, PANEL_MIN_THREAD])
	if member_list.visible:
		panels.append([member_list, PANEL_MIN_MEMBER])
	if search_panel.visible:
		panels.append([search_panel, PANEL_MIN_SEARCH])

	var total: float = 0.0
	for p in panels:
		total += p[0].custom_minimum_size.x

	if total > budget:
		# Scale all panels down proportionally, respecting hard minimums
		var excess: float = total - budget
		for p in panels:
			var share: float = p[0].custom_minimum_size.x / total
			var reduced: float = p[0].custom_minimum_size.x - excess * share
			p[0].custom_minimum_size.x = maxf(reduced, p[1])

	_clamping_panels = false

func _on_sidebar_toggle_pressed() -> void:
	AppState.toggle_channel_panel()

func _on_channel_panel_toggled(panel_visible: bool) -> void:
	if AppState.current_layout_mode != AppState.LayoutMode.COMPACT:
		sidebar.set_channel_panel_visible(panel_visible)

func _on_member_toggle_pressed() -> void:
	AppState.toggle_member_list()

func _on_member_list_toggled(_is_visible: bool) -> void:
	_update_member_list_visibility()
	_sync_handle_visibility()

func _on_search_toggle_pressed() -> void:
	AppState.toggle_search()

func _on_search_toggled(is_open: bool) -> void:
	search_panel.visible = is_open
	_sync_handle_visibility()
	if is_open:
		search_panel.activate(AppState.current_guild_id)

func _on_thread_opened(_parent_message_id: String) -> void:
	if AppState.current_layout_mode == AppState.LayoutMode.COMPACT:
		# Thread panel replaces the message view in compact mode
		message_view.visible = false

func _on_thread_closed() -> void:
	if AppState.current_layout_mode == AppState.LayoutMode.COMPACT:
		message_view.visible = true

func _on_dm_mode_entered() -> void:
	search_toggle.visible = false
	AppState.close_search()
	_update_member_list_visibility()

func _on_guild_selected(_guild_id: String) -> void:
	_update_member_list_visibility()
	_update_search_visibility()
	AppState.close_search()

func _update_member_list_visibility() -> void:
	if AppState.is_dm_mode:
		# Show member list for group DMs only
		var dm: Dictionary = {}
		for d in Client.dm_channels:
			if d["id"] == AppState.current_channel_id:
				dm = d
				break
		if dm.get("is_group", false):
			member_toggle.visible = true
			member_list.visible = AppState.member_list_visible
		else:
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

func _update_search_visibility() -> void:
	if AppState.is_dm_mode:
		search_toggle.visible = false
		search_panel.visible = false
		return
	match AppState.current_layout_mode:
		AppState.LayoutMode.COMPACT:
			search_toggle.visible = false
			search_panel.visible = false
			AppState.close_search()
		_:
			search_toggle.visible = true
			search_panel.visible = AppState.search_open

func _on_hamburger_pressed() -> void:
	AppState.toggle_sidebar_drawer()

func _on_backdrop_input(event: InputEvent) -> void:
	if _gestures.is_close_tracking:
		return
	if event is InputEventMouseButton and event.pressed:
		AppState.close_sidebar_drawer()
	elif event is InputEventScreenTouch and event.pressed:
		AppState.close_sidebar_drawer()

func _on_profile_card_requested(user_id: String, pos: Vector2) -> void:
	if _active_profile_card and is_instance_valid(_active_profile_card):
		_active_profile_card.queue_free()
	var user_data: Dictionary = Client.get_user_by_id(user_id)
	if user_data.is_empty():
		return
	_active_profile_card = ProfileCardScene.instantiate()
	add_child(_active_profile_card)
	var guild_id: String = ""
	if not AppState.is_dm_mode:
		guild_id = AppState.current_guild_id
	_active_profile_card.setup(user_data, guild_id)
	# Position near click, clamped to viewport
	await get_tree().process_frame
	var vp_size := get_viewport().get_visible_rect().size
	var card_size := _active_profile_card.size
	var x: float = clampf(pos.x, 0.0, vp_size.x - card_size.x)
	var y: float = clampf(pos.y, 0.0, vp_size.y - card_size.y)
	_active_profile_card.position = Vector2(x, y)

func _show_connecting_overlay() -> void:
	var overlay: ColorRect = ConnectingOverlayScene.instantiate()
	add_child(overlay)

func _show_welcome_screen() -> void:
	_welcome_screen = WelcomeScreenScene.instantiate()
	# Ensure it fills the VBoxContainer
	_welcome_screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_welcome_screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_area.add_child(_welcome_screen)
	# Move welcome screen above ContentBody (index 0 = ContentHeader, 1 = TopicBar, 2 = VideoGrid)
	content_area.move_child(_welcome_screen, 3)
	# Hide normal content
	content_body.visible = false
	# Listen for first server connection
	AppState.guilds_updated.connect(
		_on_first_server_added, CONNECT_ONE_SHOT
	)

func _on_first_server_added() -> void:
	if _welcome_screen and is_instance_valid(_welcome_screen):
		_welcome_screen.dismissed.connect(func() -> void:
			content_body.visible = true
			_welcome_screen = null
		)
		_welcome_screen.dismiss()
	else:
		content_body.visible = true
		_welcome_screen = null

func _show_consent_dialog() -> void:
	# Mark consent as shown immediately so the dialog never reappears,
	# regardless of how it is dismissed. Default is disabled (safe).
	Config.set_error_reporting_consent_shown()
	var dialog := ConfirmationDialog.new()
	dialog.title = "Error Reporting"
	dialog.dialog_text = (
		"Help improve daccord by sending anonymous crash and "
		+ "error reports?\n\n"
		+ "No personal data is included. You can change this "
		+ "in Settings > Notifications at any time."
	)
	dialog.ok_button_text = "Enable"
	dialog.cancel_button_text = "No thanks"
	dialog.confirmed.connect(func() -> void:
		Config.set_error_reporting_enabled(true)
		ErrorReporting.init_sentry()
		dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void:
		Config.set_error_reporting_enabled(false)
		dialog.queue_free()
	)
	add_child(dialog)
	dialog.popup_centered()

func _show_crash_toast() -> void:
	var toast := Label.new()
	toast.text = "An error report from your last session was sent."
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_font_size_override("font_size", 13)
	toast.add_theme_color_override(
		"font_color", Color(0.75, 0.75, 0.75)
	)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.19, 0.21, 0.95)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", style)
	panel.add_child(toast)
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.anchor_bottom = 1.0
	panel.anchor_top = 1.0
	panel.offset_top = -60.0
	panel.offset_bottom = -20.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var tween := create_tween()
	tween.tween_interval(4.0)
	if Config.get_reduced_motion():
		tween.tween_callback(panel.queue_free)
	else:
		tween.tween_property(panel, "modulate:a", 0.0, 1.0)
		tween.tween_callback(panel.queue_free)

func _show_toast(text: String, is_error: bool = false) -> void:
	var toast := Label.new()
	toast.text = text
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_font_size_override("font_size", 13)
	var text_color := Color(0.92, 0.92, 0.92)
	if is_error:
		text_color = Color(1.0, 0.86, 0.86)
	toast.add_theme_color_override("font_color", text_color)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = (
		Color(0.28, 0.12, 0.12, 0.95)
		if is_error
		else Color(0.18, 0.19, 0.21, 0.95)
	)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", style)
	panel.add_child(toast)
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.anchor_bottom = 1.0
	panel.anchor_top = 1.0
	panel.offset_top = -60.0
	panel.offset_bottom = -20.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var tween := create_tween()
	tween.tween_interval(4.0)
	if Config.get_reduced_motion():
		tween.tween_callback(panel.queue_free)
	else:
		tween.tween_property(panel, "modulate:a", 0.0, 1.0)
		tween.tween_callback(panel.queue_free)

func _on_voice_error(error: String) -> void:
	_show_toast("Voice error: %s" % error, true)

func _on_image_lightbox_requested(
	_url: String, texture: ImageTexture,
) -> void:
	if texture == null:
		return
	var lightbox: ColorRect = ImageLightboxScene.instantiate()
	add_child(lightbox)
	lightbox.show_image(texture)

func _on_update_download_complete(_path: String) -> void:
	var title: String = get_window().title
	if not title.ends_with("[Update ready]"):
		get_window().title = title + " [Update ready]"

func _on_profile_switched() -> void:
	# Clear tabs
	tabs.clear()
	tab_bar.clear_tabs()
	_update_tab_visibility()
	_update_tab_icons()
	_guild_icon_cache.clear()
	# Reset window title
	get_window().title = "daccord"
	# Reset topic bar
	topic_bar.visible = false
	# Show welcome screen if no servers in new profile
	if not Config.has_servers():
		_show_welcome_screen()

func _on_reauth_needed(
	server_index: int, base_url: String,
) -> void:
	var AuthDialog: PackedScene = load(
		"res://scenes/sidebar/guild_bar/auth_dialog.tscn"
	)
	var dlg: ColorRect = AuthDialog.instantiate()
	dlg.setup(base_url)
	dlg.auth_completed.connect(func(
		_url: String, token: String,
		username: String, password: String,
		_dn: String,
	) -> void:
		Config.update_server_token(server_index, token)
		Config.update_server_credentials(
			server_index, username, password,
		)
		Client.reconnect_server(server_index)
	)
	get_tree().root.add_child(dlg)
