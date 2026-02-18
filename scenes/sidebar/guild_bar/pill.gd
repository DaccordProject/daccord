extends ColorRect

enum PillState { HIDDEN, UNREAD, ACTIVE }

var pill_state: PillState = PillState.HIDDEN:
	set(value):
		pill_state = value
		if not _skip_update:
			_update_pill()

var _skip_update: bool = false

func _ready() -> void:
	_update_pill()

func _update_pill() -> void:
	match pill_state:
		PillState.HIDDEN:
			visible = false
		PillState.UNREAD:
			visible = true
			custom_minimum_size.y = 6.0
			size.y = 6.0
		PillState.ACTIVE:
			visible = true
			custom_minimum_size.y = 20.0
			size.y = 20.0

func set_state_animated(new_state: PillState) -> void:
	_skip_update = true
	pill_state = new_state
	_skip_update = false
	if new_state == PillState.HIDDEN:
		visible = false
		return
	visible = true
	var target_h := 6.0 if new_state == PillState.UNREAD else 20.0
	var tween := create_tween()
	tween.tween_property(self, "custom_minimum_size:y", target_h, 0.15)
	tween.parallel().tween_property(self, "size:y", target_h, 0.15)
