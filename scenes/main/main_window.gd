extends Control

const PANEL_HANDLE_WIDTH := 6.0
const MESSAGE_VIEW_MIN := 300.0
const PANEL_MIN_THREAD := 240.0
const PANEL_MIN_MEMBER := 180.0
const PANEL_MIN_SEARCH := 240.0
const DrawerGestures := preload("res://scenes/main/drawer_gestures.gd")
const PanelResizeHandle := preload("res://scenes/main/panel_resize_handle.gd")
const MainWindowTabs := preload("res://scenes/main/main_window_tabs.gd")
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
const VideoPipScene := preload(
	"res://scenes/video/video_pip.tscn"
)
const ToastScene := preload(
	"res://scenes/main/toast.tscn"
)

var _tabs: RefCounted
var _drawer: MainWindowDrawer
var _active_profile_card: PanelContainer = null
var _welcome_screen: Control = null
var _member_list_before_medium: bool = true
var _gestures: RefCounted
var _thread_handle: Control
var _member_handle: Control
var _search_handle: Control
var _clamping_panels: bool = false
var _update_indicator: Button = null
var _pip: PanelContainer = null

@onready var video_grid: PanelContainer = $LayoutHBox/ContentArea/VideoGrid
@onready var content_header: HBoxContainer = $LayoutHBox/ContentArea/ContentHeader
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
	_tabs = MainWindowTabs.new(tab_bar, self)
	_drawer = MainWindowDrawer.new(
		self, sidebar, drawer_container, drawer_backdrop, layout_hbox
	)
	_apply_ui_scale()
	AudioServer.set_bus_volume_db(
		0, linear_to_db(Config.voice.get_output_volume() / 100.0)
	)
	_gestures = DrawerGestures.new(self)
	AppState.channel_selected.connect(_on_channel_selected)
	AppState.sidebar_drawer_toggled.connect(_drawer.on_sidebar_drawer_toggled)
	AppState.layout_mode_changed.connect(_on_layout_mode_changed)
	tab_bar.tab_changed.connect(_tabs.on_tab_changed)
	tab_bar.tab_close_pressed.connect(_tabs.on_tab_close)
	tab_bar.active_tab_rearranged.connect(_tabs.on_tab_rearranged)
	hamburger_button.pressed.connect(_on_hamburger_pressed)
	sidebar_toggle.pressed.connect(_on_sidebar_toggle_pressed)
	member_toggle.pressed.connect(_on_member_toggle_pressed)
	search_toggle.pressed.connect(_on_search_toggle_pressed)
	AppState.channel_panel_toggled.connect(_on_channel_panel_toggled)
	AppState.member_list_toggled.connect(_on_member_list_toggled)
	AppState.search_toggled.connect(_on_search_toggled)
	AppState.dm_mode_entered.connect(_on_dm_mode_entered)
	AppState.space_selected.connect(_on_space_selected)
	AppState.reauth_needed.connect(_on_reauth_needed)
	AppState.profile_switched.connect(_on_profile_switched)
	AppState.server_removed.connect(_on_server_removed)
	drawer_backdrop.gui_input.connect(_on_backdrop_input)
	get_viewport().size_changed.connect(_on_viewport_resized)
	AppState.thread_opened.connect(_on_thread_opened)
	AppState.thread_closed.connect(_on_thread_closed)
	AppState.profile_card_requested.connect(_on_profile_card_requested)
	AppState.image_lightbox_requested.connect(_on_image_lightbox_requested)
	AppState.voice_error.connect(_on_voice_error)
	AppState.voice_view_opened.connect(_on_voice_view_opened)
	AppState.voice_view_closed.connect(_on_voice_view_closed)
	AppState.voice_left.connect(_on_voice_left_pip)
	AppState.update_available.connect(_on_update_indicator_show)
	AppState.update_download_complete.connect(_on_update_indicator_ready)

	# Update indicator in content header (hidden until update available)
	_update_indicator = Button.new()
	_update_indicator.custom_minimum_size = Vector2(44, 44)
	_update_indicator.flat = true
	_update_indicator.tooltip_text = "Update available"
	_update_indicator.icon = preload(
		"res://assets/theme/icons/update.svg"
	)
	_update_indicator.add_theme_color_override(
		"icon_normal_color", Color(0.92, 0.26, 0.27)
	)
	_update_indicator.add_theme_color_override(
		"icon_hover_color", Color(1.0, 0.35, 0.36)
	)
	_update_indicator.visible = false
	_update_indicator.pressed.connect(_on_update_indicator_pressed)
	var header: HBoxContainer = $LayoutHBox/ContentArea/ContentHeader
	header.add_child(_update_indicator)
	header.move_child(
		_update_indicator, search_toggle.get_index()
	)
	# Show if an update is already known
	if Updater.is_update_ready() or (
		not Updater.get_latest_version_info().is_empty()
		and Updater.is_newer(
			Updater.get_latest_version_info().get("version", ""),
			Client.app_version,
		)
	):
		_update_indicator.visible = true

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

	_tabs.update_visibility()

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
	var win := get_window()
	win.content_scale_factor = scale
	# Grow the window to compensate so the effective viewport stays the same.
	var base_size := Vector2i(
		ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height"),
	)
	win.size = Vector2i(base_size * scale)

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
	# Close voice view if open (triggers PiP spawn via _on_voice_view_closed)
	if AppState.is_voice_view_open:
		AppState.close_voice_view()

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
		get_window().title = "Daccord - " + channel_name
	else:
		get_window().title = "Daccord - #" + channel_name

	# Update topic bar
	if topic != "":
		topic_bar.text = topic
		topic_bar.visible = true
	else:
		topic_bar.visible = false

	# Look up space for this channel
	var space_id: String = Client._channel_to_space.get(channel_id, "")

	# Check if tab already exists
	var existing: int = _tabs.find_tab(channel_id)
	if existing >= 0:
		tab_bar.current_tab = existing
		return

	_tabs.add_tab(channel_name, channel_id, space_id)

func _on_server_removed(space_id: String) -> void:
	var was_active: bool = AppState.current_space_id == space_id
	# Clear composition state tied to the removed server
	if was_active:
		if not AppState.replying_to_message_id.is_empty():
			AppState.cancel_reply()
		if not AppState.editing_message_id.is_empty():
			AppState.editing_message_id = ""
		if AppState.thread_panel_visible:
			AppState.close_thread()
	if AppState.is_imposter_mode and AppState.imposter_space_id == space_id:
		AppState.exit_imposter_mode()

	# Remove tabs belonging to the disconnected server
	_tabs.remove_tabs_for_space(space_id)

	if _tabs.tabs.is_empty():
		# Reset navigation state
		AppState.current_space_id = ""
		AppState.current_channel_id = ""
		get_window().title = "Daccord"
		topic_bar.visible = false
		_tabs.update_visibility()
		if not Config.has_servers():
			_show_welcome_screen()
		return

	# Ensure a valid tab is selected
	var current: int = clampi(
		tab_bar.current_tab, 0, _tabs.tabs.size() - 1,
	)
	tab_bar.current_tab = current
	_tabs.select_current()
	_tabs.update_visibility()
	_tabs.update_icons()

func _on_viewport_resized() -> void:
	var vp_size := get_viewport().get_visible_rect().size
	AppState.update_layout_mode(vp_size.x, vp_size.y)
	# Recalculate drawer width if sidebar is in drawer and open
	if _drawer.is_in_drawer() and AppState.sidebar_drawer_open:
		sidebar.offset_right = _drawer.get_drawer_width()

func _on_layout_mode_changed(mode: AppState.LayoutMode) -> void:
	# When voice view is open, skip content visibility management
	if AppState.is_voice_view_open:
		# Still handle sidebar/drawer transitions
		match mode:
			AppState.LayoutMode.FULL:
				_drawer.move_sidebar_to_layout()
				sidebar.visible = true
				sidebar.set_channel_panel_visible_immediate(AppState.channel_panel_visible)
				hamburger_button.visible = false
				sidebar_toggle.visible = true
				_drawer.close_drawer_immediate()
			AppState.LayoutMode.MEDIUM:
				_drawer.move_sidebar_to_layout()
				sidebar.visible = true
				sidebar.set_channel_panel_visible_immediate(AppState.channel_panel_visible)
				hamburger_button.visible = false
				sidebar_toggle.visible = true
				_drawer.close_drawer_immediate()
			AppState.LayoutMode.COMPACT:
				_drawer.move_sidebar_to_drawer()
				sidebar.set_channel_panel_visible_immediate(true)
				hamburger_button.visible = true
				sidebar_toggle.visible = false
				_drawer.close_drawer_immediate()
		return

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
		search_panel.activate(AppState.current_space_id)

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

func _on_space_selected(_space_id: String) -> void:
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
	var space_id: String = ""
	if not AppState.is_dm_mode:
		space_id = AppState.current_space_id
	_active_profile_card.setup(user_data, space_id)
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
	# Add as full-window overlay covering sidebar + content
	add_child(_welcome_screen)
	# Hide normal layout
	layout_hbox.visible = false
	# Listen for first server connection
	if not AppState.spaces_updated.is_connected(_on_first_server_added):
		AppState.spaces_updated.connect(
			_on_first_server_added, CONNECT_ONE_SHOT
		)

func _on_first_server_added() -> void:
	# Guard: spaces_updated can fire from disconnect_server() too.
	# Only dismiss the welcome screen when a server actually exists.
	if not Config.has_servers():
		if not AppState.spaces_updated.is_connected(_on_first_server_added):
			AppState.spaces_updated.connect(
				_on_first_server_added, CONNECT_ONE_SHOT
			)
		return
	if _welcome_screen and is_instance_valid(_welcome_screen):
		_welcome_screen.dismissed.connect(func() -> void:
			layout_hbox.visible = true
			_welcome_screen = null
		)
		_welcome_screen.dismiss()
	else:
		layout_hbox.visible = true
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
	_show_toast(
		"An error report from your last session was sent."
	)

func _show_toast(text: String, is_error: bool = false) -> void:
	var toast: PanelContainer = ToastScene.instantiate()
	toast.setup(text, is_error)
	add_child(toast)

func _on_voice_view_opened(_channel_id: String) -> void:
	_remove_pip()
	content_header.visible = false
	topic_bar.visible = false
	content_body.visible = false
	video_grid.set_full_area(true)

func _on_voice_view_closed() -> void:
	content_header.visible = true
	content_body.visible = true
	# Restore topic bar based on current channel
	var topic := ""
	for ch in Client.channels:
		if ch["id"] == AppState.current_channel_id:
			topic = ch.get("topic", "")
			break
	topic_bar.visible = topic != ""
	video_grid.set_full_area(false)
	# Spawn PiP if still in voice with active video
	_maybe_spawn_pip()

func _on_voice_left_pip(_channel_id: String) -> void:
	_remove_pip()

func _maybe_spawn_pip() -> void:
	if AppState.voice_channel_id.is_empty():
		return
	# Only spawn PiP if there's any video content
	var has_video := (
		Client.get_camera_track() != null
		or Client.get_screen_track() != null
	)
	if not has_video:
		# Check remote peers
		var cid := AppState.voice_channel_id
		var my_id: String = Client.current_user.get("id", "")
		var states: Array = Client.get_voice_users(cid)
		for state in states:
			var uid: String = state.get("user_id", "")
			if uid == my_id:
				continue
			if state.get("self_video", false) or state.get("self_stream", false):
				has_video = true
				break
	if not has_video:
		return
	_pip = VideoPipScene.instantiate()
	_pip.pip_clicked.connect(_on_pip_clicked)
	add_child(_pip)

func _remove_pip() -> void:
	if _pip != null and is_instance_valid(_pip):
		_pip.queue_free()
		_pip = null

func _on_pip_clicked() -> void:
	_remove_pip()
	AppState.open_voice_view()

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

func _on_update_indicator_show(_info: Dictionary) -> void:
	_update_indicator.visible = true
	_update_indicator.tooltip_text = "Update available"

func _on_update_indicator_ready(_path: String) -> void:
	_update_indicator.visible = true
	_update_indicator.tooltip_text = "Update ready — restart to apply"

func _on_update_indicator_pressed() -> void:
	var AppSettingsScene: PackedScene = load(
		"res://scenes/user/app_settings.tscn"
	)
	if AppSettingsScene:
		var settings: ColorRect = AppSettingsScene.instantiate()
		settings.initial_page = 5 # Updates page
		get_tree().root.add_child(settings)

func _on_profile_switched() -> void:
	_tabs.clear_all()
	# Reset window title
	get_window().title = "Daccord"
	# Reset topic bar
	topic_bar.visible = false
	# Show welcome screen if no servers in new profile
	if not Config.has_servers():
		_show_welcome_screen()

func _on_reauth_needed(
	server_index: int, base_url: String,
	username: String,
) -> void:
	var AuthDialog: PackedScene = load(
		"res://scenes/sidebar/guild_bar/auth_dialog.tscn"
	)
	var dlg: ColorRect = AuthDialog.instantiate()
	dlg.setup(base_url, username)
	dlg.auth_completed.connect(func(
		_url: String, token: String,
		new_username: String, _password: String,
		_dn: String,
	) -> void:
		Config.update_server_token(server_index, token)
		Config.update_server_username(
			server_index, new_username,
		)
		Client.reconnect_server(server_index)
	)
	get_tree().root.add_child(dlg)
