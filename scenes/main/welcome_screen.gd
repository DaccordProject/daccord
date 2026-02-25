extends Control

signal dismissed()

const AddServerDialogScene := preload(
	"res://scenes/sidebar/guild_bar/add_server_dialog.tscn"
)

const BLURPLE := Color(0.345, 0.396, 0.949)
const MUTED_GRAY := Color(0.58, 0.608, 0.643)

var _pulse_tween: Tween
var _features_vbox: VBoxContainer
var _update_btn: Button

@onready var logo_label: Label = $ContentCenter/ContentVBox/LogoLabel
@onready var tagline_label: Label = $ContentCenter/ContentVBox/TaglineLabel
@onready var features_hbox: HBoxContainer = $ContentCenter/ContentVBox/FeaturesHBox
@onready var cta_button: Button = $ContentCenter/ContentVBox/CTAButton
@onready var particles: CPUParticles2D = $ParticlesLayer/FloatingParticles
@onready var settings_button: Button = $SettingsButton


func _ready() -> void:
	cta_button.pressed.connect(_on_cta_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	AppState.layout_mode_changed.connect(_on_layout_mode_changed)
	resized.connect(_on_resized)

	# Update indicator next to settings button
	_update_btn = Button.new()
	_update_btn.text = "Update Available"
	_update_btn.flat = true
	_update_btn.icon = preload(
		"res://assets/theme/icons/update.svg"
	)
	_update_btn.add_theme_color_override(
		"font_color", Color(0.92, 0.26, 0.27)
	)
	_update_btn.add_theme_color_override(
		"font_hover_color", Color(1.0, 0.35, 0.36)
	)
	_update_btn.add_theme_color_override(
		"icon_normal_color", Color(0.92, 0.26, 0.27)
	)
	_update_btn.add_theme_color_override(
		"icon_hover_color", Color(1.0, 0.35, 0.36)
	)
	_update_btn.add_theme_font_size_override("font_size", 14)
	_update_btn.visible = false
	_update_btn.pressed.connect(_on_update_pressed)
	# Position next to settings button (bottom-left)
	_update_btn.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_update_btn.anchor_top = 1.0
	_update_btn.anchor_bottom = 1.0
	_update_btn.offset_left = 120.0
	_update_btn.offset_top = -48.0
	_update_btn.offset_right = 300.0
	_update_btn.offset_bottom = -12.0
	_update_btn.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_update_btn)

	AppState.update_available.connect(_on_update_available)
	AppState.update_download_complete.connect(_on_update_ready)

	# Show if an update is already known
	if Updater.is_update_ready():
		_update_btn.text = "Update Ready"
		_update_btn.visible = true
	elif not Updater.get_latest_version_info().is_empty():
		if Updater.is_newer(
			Updater.get_latest_version_info().get("version", ""),
			Client.app_version,
		):
			_update_btn.visible = true

	# Apply initial responsive layout
	_apply_layout(AppState.current_layout_mode)

	# Position particles to span the full area
	call_deferred("_on_resized")

	# Defer entrance animation so container layout completes first
	_start_entrance_deferred()


func _on_resized() -> void:
	if particles:
		# Position at bottom center, emission spans full width
		particles.position = Vector2(size.x / 2.0, size.y)
		particles.emission_rect_extents = Vector2(size.x / 2.0, 10)


func _start_entrance_deferred() -> void:
	# Wait two frames for the full container hierarchy (CenterContainer ->
	# VBoxContainer) to resolve layout.  A single frame is not enough because
	# parent containers may still be sizing on the first pass, leaving all
	# VBox children at position.y == 0 which causes them to overlap.
	await get_tree().process_frame
	await get_tree().process_frame
	_animate_entrance()


func _animate_entrance() -> void:
	if Config.get_reduced_motion():
		return

	var elements: Array[Control] = [
		logo_label, tagline_label, features_hbox, cta_button,
	]

	# Save layout-resolved positions before offsetting so animation targets
	# are correct even if the container hasn't fully settled.
	var target_y: Array[float] = []
	for el in elements:
		target_y.append(el.position.y)
		el.modulate.a = 0.0
		el.position.y += 30.0

	# Settings + update buttons fade in from transparent
	settings_button.modulate.a = 0.0
	_update_btn.modulate.a = 0.0

	# Staggered fade in + slide up
	var tween := create_tween()
	tween.set_parallel(true)

	# Logo: 0.0 – 0.4s
	tween.tween_property(
		logo_label, "modulate:a", 1.0, 0.4
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(
		logo_label, "position:y", target_y[0], 0.4
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	# Tagline: 0.15 – 0.55s
	tween.tween_property(
		tagline_label, "modulate:a", 1.0, 0.4
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC).set_delay(0.15)
	tween.tween_property(
		tagline_label, "position:y", target_y[1], 0.4
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC).set_delay(0.15)

	# Features: 0.3 – 0.7s
	tween.tween_property(
		features_hbox, "modulate:a", 1.0, 0.4
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC).set_delay(0.3)
	tween.tween_property(
		features_hbox, "position:y", target_y[2], 0.4
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC).set_delay(0.3)

	# CTA button: 0.5 – 0.9s with scale bounce
	cta_button.pivot_offset = cta_button.size / 2.0
	cta_button.scale = Vector2(0.9, 0.9)
	tween.tween_property(
		cta_button, "modulate:a", 1.0, 0.4
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC).set_delay(0.5)
	tween.tween_property(
		cta_button, "position:y", target_y[3], 0.4
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC).set_delay(0.5)
	tween.tween_property(
		cta_button, "scale", Vector2(1.0, 1.0), 0.4
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK).set_delay(0.5)

	# Settings + update buttons: fade in at 0.5s
	tween.tween_property(
		settings_button, "modulate:a", 1.0, 0.4
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC).set_delay(0.5)
	tween.tween_property(
		_update_btn, "modulate:a", 1.0, 0.4
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC).set_delay(0.5)

	# After entrance, start pulse glow on CTA
	tween.chain().tween_callback(_start_cta_pulse)


func _start_cta_pulse() -> void:
	if Config.get_reduced_motion():
		return
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(
		cta_button, "modulate", Color(1.1, 1.1, 1.1, 1.0), 1.0
	).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_pulse_tween.tween_property(
		cta_button, "modulate", Color(1.0, 1.0, 1.0, 1.0), 1.0
	).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


func dismiss() -> void:
	if _pulse_tween:
		_pulse_tween.kill()

	if Config.get_reduced_motion():
		dismissed.emit()
		queue_free()
		return

	var tween := create_tween().set_parallel(true)

	# Fade out + slide up
	tween.tween_property(
		self, "modulate:a", 0.0, 0.3
	).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)

	tween.chain().tween_callback(func() -> void:
		dismissed.emit()
		queue_free()
	)


func _on_cta_pressed() -> void:
	var dialog: ColorRect = AddServerDialogScene.instantiate()
	get_tree().root.add_child(dialog)


func _on_settings_pressed() -> void:
	_open_app_settings()


func _on_update_available(_info: Dictionary) -> void:
	_update_btn.text = "Update Available"
	_update_btn.visible = true
	_update_btn.modulate.a = 1.0


func _on_update_ready(_path: String) -> void:
	_update_btn.text = "Update Ready"
	_update_btn.visible = true
	_update_btn.modulate.a = 1.0


func _on_update_pressed() -> void:
	_open_app_settings(5) # Updates page


func _open_app_settings(initial_page: int = -1) -> void:
	var AppSettingsScene: PackedScene = load(
		"res://scenes/user/app_settings.tscn"
	)
	if AppSettingsScene:
		var settings: ColorRect = AppSettingsScene.instantiate()
		if initial_page >= 0:
			settings.initial_page = initial_page
		get_tree().root.add_child(settings)


func _on_layout_mode_changed(mode: AppState.LayoutMode) -> void:
	_apply_layout(mode)


func _apply_layout(mode: AppState.LayoutMode) -> void:
	if mode == AppState.LayoutMode.COMPACT:
		_switch_features_to_vbox()
	else:
		_switch_features_to_hbox()


func _switch_features_to_vbox() -> void:
	if _features_vbox:
		return
	# Move children from HBox to a new VBox
	_features_vbox = VBoxContainer.new()
	_features_vbox.add_theme_constant_override("separation", 12)
	_features_vbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var children: Array[Node] = []
	for child in features_hbox.get_children():
		children.append(child)
	for child in children:
		features_hbox.remove_child(child)
		_features_vbox.add_child(child)

	features_hbox.add_child(_features_vbox)


func _switch_features_to_hbox() -> void:
	if not _features_vbox:
		return
	var children: Array[Node] = []
	for child in _features_vbox.get_children():
		children.append(child)
	for child in children:
		_features_vbox.remove_child(child)
		features_hbox.add_child(child)

	_features_vbox.queue_free()
	_features_vbox = null
