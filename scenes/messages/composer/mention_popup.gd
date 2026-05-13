extends PanelContainer

signal member_picked(member: Dictionary)
signal dismissed

const MAX_VISIBLE: int = 8
const ROW_HEIGHT: int = 32

var _candidates: Array = []
var _filtered: Array = []
var _selected_index: int = 0
var _row_buttons: Array[Button] = []

@onready var header_label: Label = $VBox/Header
@onready var rows: VBoxContainer = $VBox/Rows

func _ready() -> void:
	add_to_group("themed")
	_apply_theme()

func _apply_theme() -> void:
	var style: StyleBox = get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		style.bg_color = ThemeManager.get_color("modal_bg")
	header_label.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)

## Populate with the list of selectable members.
## [param members] is an Array of user-shaped Dictionaries (id, display_name,
## username, color, avatar).
func setup(members: Array, prefix: String) -> void:
	_candidates = members
	_filter(prefix)

## Re-filter the candidate list against [param prefix]. Returns whether any
## results remain after filtering.
func filter(prefix: String) -> bool:
	_filter(prefix)
	return not _filtered.is_empty()

func _filter(prefix: String) -> void:
	var lower: String = prefix.strip_edges().to_lower()
	_filtered.clear()
	for member in _candidates:
		if not (member is Dictionary):
			continue
		if lower.is_empty():
			_filtered.append(member)
			continue
		var dn: String = str(member.get("display_name", "")).to_lower()
		var un: String = str(member.get("username", "")).to_lower()
		if dn.begins_with(lower) or un.begins_with(lower):
			_filtered.append(member)
	# Stable sort: display_name starts-with first, then username starts-with.
	_filtered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var an: String = str(a.get("display_name", "")).to_lower()
		var bn: String = str(b.get("display_name", "")).to_lower()
		if lower.is_empty():
			return an < bn
		var a_dn_match: bool = an.begins_with(lower)
		var b_dn_match: bool = bn.begins_with(lower)
		if a_dn_match != b_dn_match:
			return a_dn_match
		return an < bn
	)
	if _filtered.size() > MAX_VISIBLE:
		_filtered.resize(MAX_VISIBLE)
	_selected_index = 0
	_rebuild_rows()

func _rebuild_rows() -> void:
	NodeUtils.free_children(rows)
	_row_buttons.clear()
	for i in _filtered.size():
		var member: Dictionary = _filtered[i]
		var btn := _make_row(member, i)
		rows.add_child(btn)
		_row_buttons.append(btn)
	_update_selection_highlight()

func _make_row(member: Dictionary, index: int) -> Button:
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.clip_text = true

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 8)
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 8
	hbox.offset_right = -8
	btn.add_child(hbox)

	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(20, 20)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var col: Color = member.get("color", ThemeManager.get_color("accent"))
	swatch.color = col
	hbox.add_child(swatch)

	var letter := Label.new()
	var dn_full: String = str(member.get("display_name", "?"))
	letter.text = dn_full.substr(0, 1).to_upper() if not dn_full.is_empty() else "?"
	letter.add_theme_font_size_override("font_size", 11)
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	letter.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Pick legible text color over the swatch.
	var luminance: float = 0.299 * col.r + 0.587 * col.g + 0.114 * col.b
	letter.add_theme_color_override(
		"font_color", Color.BLACK if luminance > 0.5 else Color.WHITE
	)
	swatch.add_child(letter)

	var name_label := Label.new()
	name_label.text = dn_full
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hbox.add_child(name_label)

	var un_str: String = str(member.get("username", ""))
	if not un_str.is_empty() and un_str.to_lower() != dn_full.to_lower():
		var un_label := Label.new()
		un_label.text = "@" + un_str
		un_label.add_theme_font_size_override("font_size", 11)
		un_label.add_theme_color_override(
			"font_color", ThemeManager.get_color("text_muted")
		)
		un_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		hbox.add_child(un_label)

	btn.pressed.connect(func() -> void:
		_pick_index(index)
	)
	btn.mouse_entered.connect(func() -> void:
		_set_selected(index, false)
	)
	return btn

func _update_selection_highlight() -> void:
	var hover_color: Color = ThemeManager.get_color("button_hover")
	for i in _row_buttons.size():
		var btn := _row_buttons[i]
		if i == _selected_index:
			var sb := StyleBoxFlat.new()
			sb.bg_color = hover_color
			sb.corner_radius_top_left = 4
			sb.corner_radius_top_right = 4
			sb.corner_radius_bottom_left = 4
			sb.corner_radius_bottom_right = 4
			btn.add_theme_stylebox_override("normal", sb)
		else:
			btn.remove_theme_stylebox_override("normal")

func _set_selected(index: int, _scroll: bool = true) -> void:
	if index < 0 or index >= _row_buttons.size():
		return
	_selected_index = index
	_update_selection_highlight()

## Move the highlighted row by [param delta] (typically -1 or +1).
func move_selection(delta: int) -> void:
	if _row_buttons.is_empty():
		return
	var count: int = _row_buttons.size()
	_selected_index = (_selected_index + delta + count) % count
	_update_selection_highlight()

## Pick the currently highlighted row. Returns true if a pick was emitted.
func pick_selected() -> bool:
	if _selected_index < 0 or _selected_index >= _filtered.size():
		return false
	_pick_index(_selected_index)
	return true

func _pick_index(index: int) -> void:
	if index < 0 or index >= _filtered.size():
		return
	member_picked.emit(_filtered[index])

## Whether the popup currently has any visible results.
func has_results() -> bool:
	return not _filtered.is_empty()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.pressed:
		var global_rect := get_global_rect()
		if not global_rect.has_point(event.global_position):
			dismissed.emit()
