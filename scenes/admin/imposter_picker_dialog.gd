extends ColorRect

var _guild_id: String = ""
var _selected_role: Dictionary = {}
var _is_custom: bool = false
var _custom_perm_checks: Dictionary = {} # perm_name -> CheckBox

@onready var role_list: VBoxContainer = $CenterContainer/Panel/VBox/Content/RoleScroll/RoleList
@onready var custom_panel: VBoxContainer = $CenterContainer/Panel/VBox/Content/CustomScroll/CustomPanel
@onready var custom_scroll: ScrollContainer = $CenterContainer/Panel/VBox/Content/CustomScroll
@onready var perm_list: VBoxContainer = $CenterContainer/Panel/VBox/Content/CustomScroll/CustomPanel/PermList
@onready var preview_button: Button = $CenterContainer/Panel/VBox/Buttons/PreviewButton
@onready var cancel_button: Button = $CenterContainer/Panel/VBox/Buttons/CancelButton
@onready var close_button: Button = $CenterContainer/Panel/VBox/Header/CloseButton

func _ready() -> void:
	preview_button.pressed.connect(_on_preview)
	cancel_button.pressed.connect(_close)
	close_button.pressed.connect(_close)
	gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			_close()
	)

func setup(guild_id: String) -> void:
	_guild_id = guild_id
	_build_role_list()
	_build_perm_checkboxes()
	custom_scroll.visible = false

func _build_role_list() -> void:
	for child in role_list.get_children():
		child.queue_free()

	var roles: Array = Client.get_roles_for_guild(_guild_id)
	# Sort by position descending (highest first)
	roles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.get("position", 0) > b.get("position", 0)
	)

	for role in roles:
		var btn := Button.new()
		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 36)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var hbox := HBoxContainer.new()
		hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_theme_constant_override("separation", 8)

		# Color dot
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(12, 12)
		dot.size = Vector2(12, 12)
		dot.color = role.get("color", Color.GRAY)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(dot)

		var label := Label.new()
		label.text = role.get("name", "Unknown")
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(label)

		btn.add_child(hbox)
		btn.pressed.connect(_on_role_selected.bind(role))
		role_list.add_child(btn)

	# Custom option at bottom
	var sep := HSeparator.new()
	role_list.add_child(sep)

	var custom_btn := Button.new()
	custom_btn.text = "Custom..."
	custom_btn.flat = true
	custom_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	custom_btn.custom_minimum_size = Vector2(0, 36)
	custom_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_btn.pressed.connect(_on_custom_selected)
	role_list.add_child(custom_btn)

func _build_perm_checkboxes() -> void:
	for child in perm_list.get_children():
		child.queue_free()
	_custom_perm_checks.clear()

	for perm in AccordPermission.all():
		var check := CheckBox.new()
		check.text = perm.replace("_", " ").capitalize()
		check.add_theme_font_size_override("font_size", 13)
		perm_list.add_child(check)
		_custom_perm_checks[perm] = check

func _on_role_selected(role: Dictionary) -> void:
	_selected_role = role
	_is_custom = false
	custom_scroll.visible = false
	# Highlight selected role button
	for child in role_list.get_children():
		if child is Button:
			child.modulate = Color(1, 1, 1)
	# Find the pressed button (the one that triggered this call)
	# and highlight it
	for child in role_list.get_children():
		if child is Button and child.is_pressed():
			child.modulate = Color(0.345, 0.396, 0.949)

func _on_custom_selected() -> void:
	_is_custom = true
	_selected_role = {}
	custom_scroll.visible = true

func _on_preview() -> void:
	var role_data: Dictionary
	if _is_custom:
		var perms: Array = []
		for perm_name in _custom_perm_checks:
			var check: CheckBox = _custom_perm_checks[perm_name]
			if check.button_pressed:
				perms.append(perm_name)
		role_data = {
			"name": "Custom",
			"permissions": perms,
			"guild_id": _guild_id,
		}
	elif not _selected_role.is_empty():
		role_data = {
			"name": _selected_role.get("name", "Unknown"),
			"permissions": _selected_role.get("permissions", []),
			"guild_id": _guild_id,
		}
	else:
		return

	AppState.enter_imposter_mode(role_data)
	_close()

func _close() -> void:
	queue_free()
