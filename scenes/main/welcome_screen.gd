extends Control

signal dismissed()

const AddServerDialogScene := preload(
	"res://scenes/sidebar/guild_bar/add_server_dialog.tscn"
)

const BLURPLE := Color(0.345, 0.396, 0.949)
const MUTED_GRAY := Color(0.58, 0.608, 0.643)

var _pulse_tween: Tween
var _features_vbox: VBoxContainer

@onready var logo_label: Label = $ContentCenter/ContentVBox/LogoLabel
@onready var tagline_label: Label = $ContentCenter/ContentVBox/TaglineLabel
@onready var features_hbox: HBoxContainer = $ContentCenter/ContentVBox/FeaturesHBox
@onready var cta_button: Button = $ContentCenter/ContentVBox/CTAButton
@onready var particles: CPUParticles2D = $ParticlesLayer/FloatingParticles


func _ready() -> void:
	cta_button.pressed.connect(_on_cta_pressed)
	AppState.layout_mode_changed.connect(_on_layout_mode_changed)
	resized.connect(_on_resized)

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
	# Wait one frame for the VBoxContainer to lay out its children,
	# so position.y values reflect the real layout (not default 0).
	await get_tree().process_frame
	_animate_entrance()


func _animate_entrance() -> void:
	if Config.get_reduced_motion():
		return

	# Prepare: hide all content, offset downward
	var elements: Array[Control] = [
		logo_label, tagline_label, features_hbox, cta_button,
	]
	for el in elements:
		el.modulate.a = 0.0
		el.position.y += 30.0

	# Staggered fade in + slide up
	var tween := create_tween()
	tween.set_parallel(true)

	# Logo: 0.0 – 0.4s
	tween.tween_property(
		logo_label, "modulate:a", 1.0, 0.4
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(
		logo_label, "position:y", logo_label.position.y - 30.0, 0.4
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	# Tagline: 0.15 – 0.55s
	tween.tween_property(
		tagline_label, "modulate:a", 1.0, 0.4
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC).set_delay(0.15)
	tween.tween_property(
		tagline_label, "position:y", tagline_label.position.y - 30.0, 0.4
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC).set_delay(0.15)

	# Features: 0.3 – 0.7s
	tween.tween_property(
		features_hbox, "modulate:a", 1.0, 0.4
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC).set_delay(0.3)
	tween.tween_property(
		features_hbox, "position:y", features_hbox.position.y - 30.0, 0.4
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC).set_delay(0.3)

	# CTA button: 0.5 – 0.9s with scale bounce
	cta_button.pivot_offset = cta_button.size / 2.0
	cta_button.scale = Vector2(0.9, 0.9)
	tween.tween_property(
		cta_button, "modulate:a", 1.0, 0.4
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC).set_delay(0.5)
	tween.tween_property(
		cta_button, "position:y", cta_button.position.y - 30.0, 0.4
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC).set_delay(0.5)
	tween.tween_property(
		cta_button, "scale", Vector2(1.0, 1.0), 0.4
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK).set_delay(0.5)

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
