extends PanelContainer

@onready var role_label: Label = $HBox/RoleLabel
@onready var exit_button: Button = $HBox/ExitButton

func _ready() -> void:
	exit_button.pressed.connect(func(): AppState.exit_imposter_mode())
	AppState.imposter_mode_changed.connect(_on_imposter_mode_changed)
	visible = AppState.is_imposter_mode
	if AppState.is_imposter_mode:
		role_label.text = "Previewing as %s" % AppState.imposter_role_name

func _on_imposter_mode_changed(active: bool) -> void:
	visible = active
	if active:
		role_label.text = "Previewing as %s" % AppState.imposter_role_name
