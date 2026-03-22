extends Control
const PANEL_HANDLE_WIDTH := 6.0
const _MEMORY_BUDGET_BYTES: int = 300 * 1024 * 1024 # 300 MB
const MESSAGE_VIEW_MIN := 300.0
const PANEL_MIN_THREAD := 240.0
const PANEL_MIN_MEMBER := 180.0
const PANEL_MIN_SEARCH := 240.0
const PANEL_MIN_VOICE_TEXT := 240.0
const DrawerGestures := preload("res://scenes/main/drawer_gestures.gd")
const PanelResizeHandle := preload("res://scenes/main/panel_resize_handle.gd")
const MainWindowVoiceViewClass := preload("res://scenes/main/main_window_voice_view.gd")
const MainWindowTabs := preload("res://scenes/main/main_window_tabs.gd")
const MainWindowOverlaysClass := preload(
	"res://scenes/main/main_window_overlays.gd"
)

var _tabs: RefCounted
var _drawer: MainWindowDrawer
var _voice_view: RefCounted # MainWindowVoiceView
var _overlays: RefCounted # MainWindowOverlays
var _member_list_before_medium: bool = true
var _gestures: RefCounted
var _thread_handle: Control
var _member_handle: Control
var _search_handle: Control
var _voice_text_handle: Control
var _clamping_panels: bool = false
var _update_indicator: Button = null
var _memory_timer: Timer
var _voice_bar_in_content: bool = false

@onready var video_grid: PanelContainer = $LayoutHBox/ContentArea/VideoGrid
@onready var content_header: PanelContainer = $LayoutHBox/ContentArea/ContentHeader
@onready var layout_hbox: HBoxContainer = $LayoutHBox
@onready var sidebar: HBoxContainer = $LayoutHBox/Sidebar
@onready var content_area: VBoxContainer = $LayoutHBox/ContentArea
@onready var hamburger_button: Button = %HamburgerButton
@onready var sidebar_toggle: Button = %SidebarToggle
@onready var tab_bar: TabBar = %TabBar
@onready var header_spacer: Control = \
	$LayoutHBox/ContentArea/ContentHeader/ContentHeaderHBox/HeaderSpacer
@onready var search_toggle: Button = %SearchToggle
@onready var member_toggle: Button = %MemberListToggle
@onready var topic_bar: Label = $LayoutHBox/ContentArea/TopicBar
@onready var content_body: HBoxContainer = $LayoutHBox/ContentArea/ContentBody
@onready var voice_text_panel: PanelContainer = $LayoutHBox/ContentArea/ContentBody/VoiceTextPanel
@onready var voice_view_body: HBoxContainer = $LayoutHBox/ContentArea/VoiceViewBody
@onready var discovery_panel: PanelContainer = $LayoutHBox/DiscoveryPanel
@onready var message_view: PanelContainer = $LayoutHBox/ContentArea/ContentBody/MessageView
@onready var thread_panel: PanelContainer = $LayoutHBox/ContentArea/ContentBody/ThreadPanel
@onready var member_list: PanelContainer = $LayoutHBox/ContentArea/ContentBody/MemberList
@onready var search_panel: PanelContainer = $LayoutHBox/ContentArea/ContentBody/SearchPanel
@onready var voice_bar: PanelContainer = $LayoutHBox/Sidebar/ChannelPanel/VoiceBar
@onready var channel_panel: VBoxContainer = $LayoutHBox/Sidebar/ChannelPanel
@onready var drawer_backdrop: ColorRect = $DrawerBackdrop
@onready var drawer_container: Control = $DrawerContainer
@onready var member_drawer_backdrop: ColorRect = $MemberDrawerBackdrop
@onready var member_drawer_container: Control = $MemberDrawerContainer

func _ready() -> void:
	add_to_group("themed")
	_tabs = MainWindowTabs.new(tab_bar, self, header_spacer)
	_drawer = MainWindowDrawer.new(
		self, sidebar, drawer_container, drawer_backdrop, layout_hbox
	)
	_drawer.member_list = member_list
	_drawer.member_drawer_container = member_drawer_container
	_drawer.member_drawer_backdrop = member_drawer_backdrop
	_drawer.content_body = content_body
	_voice_view = MainWindowVoiceViewClass.new(self)
	_overlays = MainWindowOverlaysClass.new(self, layout_hbox)
	_apply_ui_scale()
	# Cap FPS on mobile to save battery — a chat app doesn't need 120Hz.
	if OS.has_feature("mobile"):
		Engine.max_fps = 60
	AudioServer.set_bus_volume_db(
		0, linear_to_db(Config.voice.get_output_volume() / 100.0)
	)
	_gestures = DrawerGestures.new(self)
	AppState.channel_selected.connect(_on_channel_selected)
	AppState.sidebar_drawer_toggled.connect(_drawer.on_sidebar_drawer_toggled)
	AppState.member_drawer_toggled.connect(_drawer.on_member_drawer_toggled)
	member_drawer_backdrop.gui_input.connect(_on_member_backdrop_input)
	AppState.layout_mode_changed.connect(_on_layout_mode_changed)
	tab_bar.tab_changed.connect(_tabs.on_tab_changed)
	tab_bar.tab_close_pressed.connect(_tabs.on_tab_close)
	tab_bar.active_tab_rearranged.connect(_tabs.on_tab_rearranged)
	tab_bar.gui_input.connect(_on_tab_bar_input)
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
	AppState.profile_card_requested.connect(
		_overlays.on_profile_card_requested
	)
	AppState.image_lightbox_requested.connect(
		_overlays.on_image_lightbox_requested
	)
	AppState.voice_error.connect(func(e: String) -> void:
		_overlays.show_toast(tr("Voice error: %s") % e, true)
	)
	AppState.voice_joined.connect(_on_voice_joined_reparent)
	AppState.voice_left.connect(_on_voice_left_reparent)
	AppState.voice_view_opened.connect(_on_voice_view_opened)
	AppState.voice_view_closed.connect(_on_voice_view_closed)
	AppState.voice_left.connect(_on_voice_left_pip)
	AppState.update_available.connect(_on_update_indicator_show)
	AppState.update_download_complete.connect(_on_update_indicator_ready)
	AppState.config_changed.connect(_on_config_changed)
	AppState.voice_text_opened.connect(
		_sync_handle_visibility.unbind(1)
	)
	AppState.voice_text_closed.connect(_sync_handle_visibility)
	AppState.discovery_opened.connect(_on_discovery_opened)
	AppState.discovery_closed.connect(_on_discovery_closed)
	AppState.toast_requested.connect(_overlays.show_toast)

	# Update indicator in content header (hidden until update available)
	_update_indicator = Button.new()
	_update_indicator.custom_minimum_size = Vector2(44, 44)
	_update_indicator.flat = true
	_update_indicator.tooltip_text = tr("Update available")
	_update_indicator.icon = preload(
		"res://assets/theme/icons/update.svg"
	)
	_update_indicator.add_theme_color_override(
		"icon_normal_color", ThemeManager.get_color("error")
	)
	_update_indicator.add_theme_color_override(
		"icon_hover_color", ThemeManager.get_color("error_hover")
	)
	_update_indicator.visible = false
	_update_indicator.pressed.connect(_on_update_indicator_pressed)
	var header: HBoxContainer = $LayoutHBox/ContentArea/ContentHeader/ContentHeaderHBox
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

	# Style content header background
	var header_style := StyleBoxFlat.new()
	header_style.bg_color = ThemeManager.get_color("content_bg")
	content_header.add_theme_stylebox_override("panel", header_style)

	# Style topic bar
	ThemeManager.style_label(topic_bar, 12, "text_muted")

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

	_voice_text_handle = PanelResizeHandle.new(
		voice_text_panel, 240.0, 500.0, 300.0,
	)
	content_body.add_child(_voice_text_handle)
	content_body.move_child(
		_voice_text_handle, voice_text_panel.get_index()
	)

	_sync_handle_visibility()
	content_body.resized.connect(_clamp_panel_widths)

	_tabs.update_visibility()

	# Mobile optimisations: safe-area insets + memory budget monitor
	if OS.has_feature("mobile"):
		_apply_safe_area_insets()
		_memory_timer = Timer.new()
		_memory_timer.wait_time = 60.0
		_memory_timer.timeout.connect(_check_memory_budget)
		add_child(_memory_timer)
		_memory_timer.start()

	# Apply initial layout
	_on_viewport_resized()

	# Error reporting consent (first launch only)
	if not Config.has_error_reporting_preference():
		_overlays.call_deferred("show_consent_dialog")

	# Crash recovery toast
	if Config.get_error_reporting_enabled() and ErrorReporting._initialized:
		var last_id: String = ErrorReporting.get_last_event_id()
		if not last_id.is_empty():
			_overlays.call_deferred("show_crash_toast")

	# Welcome screen for first launch (no servers configured)
	if not Config.has_servers():
		_overlays.show_welcome_screen()

func _apply_ui_scale() -> void:
	var scale: float = Config.get_ui_scale()
	if scale <= 0.0:
		scale = _auto_ui_scale()
	var win := get_window()
	win.content_scale_factor = scale
	# On web/mobile the host owns the viewport — skip window resize/reposition.
	if OS.has_feature("web") or OS.has_feature("mobile"):
		return
	# Grow/shrink the window to compensate so the effective viewport stays the same.
	var base_size := Vector2i(
		ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height"),
	)
	win.size = Vector2i(base_size * scale)
	# Re-centre the window after the DPI resize.
	var screen_id: int = DisplayServer.window_get_current_screen(
		DisplayServer.MAIN_WINDOW_ID
	)
	var screen_pos: Vector2i = DisplayServer.screen_get_position(screen_id)
	var screen_size: Vector2i = DisplayServer.screen_get_size(screen_id)
	win.position = screen_pos + (screen_size - win.size) / 2

func _auto_ui_scale() -> float:
	var allow_hidpi: bool = ProjectSettings.get_setting(
		"display/window/dpi/allow_hidpi"
	)
	if not allow_hidpi:
		return 1.0
	var screen: int = DisplayServer.window_get_current_screen(
		DisplayServer.MAIN_WINDOW_ID
	)
	# On mobile, derive scale from DPI since screen_get_scale() is unreliable.
	# 160 DPI is the Android baseline density (mdpi = 1x).
	if OS.has_feature("mobile"):
		var dpi: int = DisplayServer.screen_get_dpi(screen)
		if dpi <= 160:
			return 1.0
		return clampf(float(dpi) / 160.0, 1.0, 3.0)
	var screen_scale: float = DisplayServer.screen_get_scale(screen)
	if screen_scale <= 1.0:
		return 1.0
	return clampf(screen_scale, 1.0, 3.0)

func _apply_safe_area_insets() -> void:
	var ss := DisplayServer.screen_get_size()
	var sa: Rect2i = DisplayServer.get_display_safe_area()
	var s: float = get_window().content_scale_factor
	offset_top = sa.position.y / s
	offset_left = sa.position.x / s
	offset_bottom = -(ss.y - sa.position.y - sa.size.y) / s
	offset_right = -(ss.x - sa.position.x - sa.size.x) / s

func _check_memory_budget() -> void:
	var usage: int = OS.get_static_memory_usage()
	if usage > _MEMORY_BUDGET_BYTES:
		push_warning(
			"Memory budget exceeded: %.0f MB (budget: 300 MB)"
			% (usage / 1048576.0)
		)

func _input(event: InputEvent) -> void:
	if AppState.current_layout_mode != AppState.LayoutMode.COMPACT:
		return
	_gestures.handle_input(event)

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _handle_back_navigation():
		get_viewport().set_input_as_handled()

func _handle_back_navigation() -> bool:
	# Pop the most recent entry from the navigation history and close it.
	var entry: StringName = AppState.nav_history.pop()
	var handled := true
	match entry:
		&"drawer":
			AppState.close_sidebar_drawer()
		&"thread":
			AppState.close_thread()
		&"voice_view":
			AppState.close_voice_view()
		&"discovery":
			AppState.close_discovery()
		&"member_drawer":
			AppState.close_member_drawer()
		_:
			handled = false
	if handled:
		return true
	# Nothing on stack — in COMPACT mode, toggle the sidebar drawer.
	if AppState.current_layout_mode == AppState.LayoutMode.COMPACT:
		if not AppState.sidebar_drawer_open:
			AppState.toggle_sidebar_drawer()
			return true
	return false

func _on_channel_selected(channel_id: String) -> void:
	# Close discovery panel if open
	if AppState.is_discovery_open:
		AppState.close_discovery()

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
		get_window().title = tr("Daccord - %s") % channel_name
	else:
		get_window().title = tr("Daccord - #%s") % channel_name

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
			_overlays.show_welcome_screen()
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
	# Move voice bar between sidebar and content area based on layout
	if not AppState.voice_channel_id.is_empty():
		if mode == AppState.LayoutMode.COMPACT:
			_move_voice_bar_to_content()
		else:
			_move_voice_bar_to_sidebar()

	if AppState.is_voice_view_open:
		# Still handle sidebar/drawer transitions
		if mode == AppState.LayoutMode.COMPACT:
			_drawer.move_sidebar_to_drawer()
			_drawer.move_member_to_drawer()
			sidebar.set_channel_panel_visible_immediate(true)
			hamburger_button.visible = true
			sidebar_toggle.visible = false
			# Hide voice text in compact mode
			voice_text_panel.visible = false
			_voice_text_handle.visible = false
		else:
			_drawer.move_sidebar_to_layout()
			_drawer.move_member_to_layout()
			_drawer.close_member_drawer_immediate()
			sidebar.visible = true
			sidebar.set_channel_panel_visible_immediate(AppState.channel_panel_visible)
			hamburger_button.visible = false
			sidebar_toggle.visible = true
			# Restore voice text if it was open
			voice_text_panel.visible = (
				not AppState.voice_text_channel_id.is_empty()
			)
			_voice_text_handle.visible = (
				not AppState.voice_text_channel_id.is_empty()
			)
		_drawer.close_drawer_immediate()
		return

	match mode:
		AppState.LayoutMode.FULL, AppState.LayoutMode.MEDIUM:
			_drawer.move_sidebar_to_layout()
			_drawer.move_member_to_layout()
			_drawer.close_member_drawer_immediate()
			sidebar.visible = true
			sidebar.set_channel_panel_visible_immediate(AppState.channel_panel_visible)
			hamburger_button.visible = false
			sidebar_toggle.visible = true
			_drawer.close_drawer_immediate()
			if mode == AppState.LayoutMode.FULL:
				AppState.member_list_visible = _member_list_before_medium
			else:
				_member_list_before_medium = AppState.member_list_visible
				AppState.member_list_visible = false
			message_view.visible = true
			_update_member_list_visibility()
			_update_search_visibility()
			_sync_handle_visibility()
		AppState.LayoutMode.COMPACT:
			_drawer.move_sidebar_to_drawer()
			_drawer.move_member_to_drawer()
			sidebar.set_channel_panel_visible_immediate(true)
			hamburger_button.visible = true
			sidebar_toggle.visible = false
			_drawer.close_drawer_immediate()
			_drawer.close_member_drawer_immediate()
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
	# Voice text handle lives in VoiceViewBody during voice view
	if not AppState.is_voice_view_open:
		_voice_text_handle.visible = (
			voice_text_panel.visible and not is_compact
		)
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
	var vt_in_body: bool = (
		not AppState.is_voice_view_open
	)
	if _voice_text_handle.visible and vt_in_body:
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
	if voice_text_panel.visible and vt_in_body:
		panels.append([voice_text_panel, PANEL_MIN_VOICE_TEXT])

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

func _on_space_selected(space_id: String) -> void:
	AppState.close_voice_text()
	_update_member_list_visibility()
	_update_search_visibility()
	AppState.close_search()
	_check_rules_interstitial(space_id)

func _check_rules_interstitial(space_id: String) -> void:
	if Config.has_rules_accepted(space_id):
		return
	var space: Dictionary = Client.get_space_by_id(space_id)
	var rules_ch: String = space.get("rules_channel_id", "")
	if rules_ch.is_empty():
		return
	var RulesDialog := preload(
		"res://scenes/admin/rules_interstitial_dialog.tscn"
	)
	var dialog: ModalBase = RulesDialog.instantiate()
	dialog.setup(space_id, rules_ch)
	get_tree().root.add_child(dialog)

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
	var is_compact: bool = (
		AppState.current_layout_mode == AppState.LayoutMode.COMPACT
	)
	member_toggle.visible = not is_compact
	member_list.visible = not is_compact and AppState.member_list_visible

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

func _on_member_backdrop_input(event: InputEvent) -> void:
	if _gestures.is_member_close_tracking:
		return
	if event.pressed and (event is InputEventMouseButton
			or event is InputEventScreenTouch):
		AppState.close_member_drawer()

func _hide_drawer_nodes() -> void:
	_drawer.hide_drawer_nodes()

func _hide_member_drawer_nodes() -> void:
	_drawer.hide_member_drawer_nodes()

func _on_voice_view_opened(channel_id: String) -> void:
	_voice_view.on_voice_view_opened(
		channel_id, topic_bar,
		content_body, voice_text_panel, video_grid,
		voice_view_body, _voice_text_handle,
	)

func _on_voice_view_closed() -> void:
	_voice_view.on_voice_view_closed(
		content_body, message_view,
		topic_bar, video_grid, voice_view_body,
		_voice_text_handle, _sync_handle_visibility,
	)

func _on_voice_left_pip(channel_id: String) -> void:
	_voice_view.on_voice_left(channel_id)

func _on_voice_joined_reparent(_channel_id: String) -> void:
	if AppState.current_layout_mode == AppState.LayoutMode.COMPACT:
		_move_voice_bar_to_content()

func _on_voice_left_reparent(_channel_id: String) -> void:
	_move_voice_bar_to_sidebar()

func _move_voice_bar_to_content() -> void:
	if _voice_bar_in_content:
		return
	_voice_bar_in_content = true
	channel_panel.remove_child(voice_bar)
	content_area.add_child(voice_bar)
	# Place before ContentBody so it sits between the header and messages
	content_area.move_child(voice_bar, content_body.get_index())

func _move_voice_bar_to_sidebar() -> void:
	if not _voice_bar_in_content:
		return
	_voice_bar_in_content = false
	content_area.remove_child(voice_bar)
	channel_panel.add_child(voice_bar)
	# Place before UserBar (last child)
	var user_bar_idx: int = channel_panel.get_child_count() - 1
	channel_panel.move_child(voice_bar, user_bar_idx)

func _on_update_indicator_show(_info: Dictionary) -> void:
	_update_indicator.visible = true
	_update_indicator.tooltip_text = tr("Update available")

func _on_update_indicator_ready(_path: String) -> void:
	_update_indicator.visible = true
	_update_indicator.tooltip_text = tr("Update ready — restart to apply")

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
		_overlays.show_welcome_screen()

func _on_reauth_needed(
	server_index: int, base_url: String, username: String,
) -> void:
	var AuthDialog: PackedScene = load(
		"res://scenes/sidebar/guild_bar/auth_dialog.tscn"
	)
	var dlg: ColorRect = AuthDialog.instantiate()
	dlg.setup(base_url, username)
	dlg.auth_completed.connect(func(
		_url: String, token: String, new_username: String,
		_password: String, _dn: String,
	) -> void:
		Config.update_server_token(server_index, token)
		Config.update_server_username(server_index, new_username)
		Client.reconnect_server(server_index)
	)
	get_tree().root.add_child(dlg)

func _on_config_changed(section: String, key: String) -> void:
	if section == "accessibility" and key == "ui_scale":
		_apply_ui_scale()

func _on_discovery_opened() -> void:
	AppState.close_sidebar_drawer()
	discovery_panel.visible = true
	discovery_panel.activate()
	content_area.visible = false
	sidebar.set_channel_panel_visible_immediate(false)

func _on_discovery_closed() -> void:
	discovery_panel.visible = false
	content_area.visible = true
	if AppState.current_layout_mode != AppState.LayoutMode.COMPACT:
		sidebar.set_channel_panel_visible_immediate(AppState.channel_panel_visible)
	else:
		sidebar.set_channel_panel_visible_immediate(true)
	_update_member_list_visibility()
	_update_search_visibility()
	_sync_handle_visibility()

func _on_tab_bar_input(event: InputEvent) -> void:
	_tabs.handle_tab_bar_input(event)

func _apply_theme() -> void:
	drawer_backdrop.color = ThemeManager.get_color("overlay")
	member_drawer_backdrop.color = ThemeManager.get_color("overlay")
	var header_sb: StyleBox = content_header.get_theme_stylebox("panel")
	if header_sb is StyleBoxFlat:
		header_sb.bg_color = ThemeManager.get_color("content_bg")
	# Re-apply inline color overrides for long-lived nodes
	topic_bar.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	_update_indicator.add_theme_color_override(
		"icon_normal_color", ThemeManager.get_color("error")
	)
	_update_indicator.add_theme_color_override(
		"icon_hover_color", ThemeManager.get_color("error_hover")
	)
