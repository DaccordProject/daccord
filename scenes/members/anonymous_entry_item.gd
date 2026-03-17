extends Control

## Non-interactive member list row showing "N anonymous users".
## Pinned to the bottom of the member list in guest mode.

var _count: int = 0

@onready var avatar: ColorRect = $HBox/Avatar
@onready var display_name: Label = $HBox/DisplayName
@onready var status_dot: ColorRect = $HBox/StatusDot

func _ready() -> void:
	add_to_group("themed")
	_apply_theme()

func _apply_theme() -> void:
	if display_name:
		display_name.add_theme_color_override(
			"font_color", ThemeManager.get_color("text_muted")
		)
	if status_dot:
		status_dot.color = ThemeManager.get_color("text_muted")

func setup(data: Dictionary) -> void:
	_count = data.get("count", 0)
	_update_label()
	if avatar:
		avatar.color = ThemeManager.get_color("text_muted")
	if status_dot:
		status_dot.visible = false

func update_count(count: int) -> void:
	_count = count
	_update_label()

func _update_label() -> void:
	if display_name:
		if _count == 1:
			display_name.text = "1 anonymous user"
		else:
			display_name.text = "%d anonymous users" % _count
