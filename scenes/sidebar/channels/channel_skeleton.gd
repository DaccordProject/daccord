extends VBoxContainer

const SHIMMER_SHADER := preload("res://assets/theme/skeleton_shimmer.gdshader")
const SHIMMER_DURATION := 1.2

var _bar_color: Color
var _shimmer_offset: float = -0.5
var _materials: Array[ShaderMaterial] = []

# Simulate a channel list: 2 uncategorized, a category header + 3 channels,
# another category + 2 channels.
var _layout: Array = [
	{"type": "channel", "width": 140},
	{"type": "channel", "width": 110},
	{"type": "spacer"},
	{"type": "category", "width": 90},
	{"type": "channel", "width": 160},
	{"type": "channel", "width": 120},
	{"type": "channel", "width": 100},
	{"type": "spacer"},
	{"type": "category", "width": 70},
	{"type": "channel", "width": 130},
	{"type": "channel", "width": 150},
]

func _ready() -> void:
	add_to_group("themed")
	_bar_color = ThemeManager.get_color("button_hover")
	_build_skeleton()
	if Config.get_reduced_motion():
		set_process(false)
	AppState.reduce_motion_changed.connect(_on_reduce_motion_changed)

func _process(delta: float) -> void:
	_shimmer_offset += delta / SHIMMER_DURATION
	if _shimmer_offset > 1.5:
		_shimmer_offset = -0.5
	for mat in _materials:
		mat.set_shader_parameter("shimmer_offset", _shimmer_offset)

func _build_skeleton() -> void:
	for entry in _layout:
		match entry["type"]:
			"category":
				var row := HBoxContainer.new()
				row.add_theme_constant_override("separation", 4)
				var margin := Control.new()
				margin.custom_minimum_size = Vector2(8, 0)
				row.add_child(margin)
				var bar := _make_bar(int(entry["width"]), 10, 0.1)
				row.add_child(bar)
				add_child(row)
			"channel":
				var row := HBoxContainer.new()
				row.add_theme_constant_override("separation", 8)
				row.custom_minimum_size = Vector2(0, 32)
				var margin := Control.new()
				margin.custom_minimum_size = Vector2(8, 0)
				row.add_child(margin)
				# Channel icon placeholder
				var icon := _make_bar(16, 16, 0.1)
				icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				row.add_child(icon)
				# Channel name placeholder
				var name_bar := _make_bar(int(entry["width"]), 14, 0.1)
				name_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				row.add_child(name_bar)
				add_child(row)
			"spacer":
				var spacer := Control.new()
				spacer.custom_minimum_size = Vector2(0, 8)
				add_child(spacer)

func _make_bar(w: int, h: int, radius: float) -> ColorRect:
	var bar := ColorRect.new()
	bar.custom_minimum_size = Vector2(w, h)
	bar.color = _bar_color
	var mat := ShaderMaterial.new()
	mat.shader = SHIMMER_SHADER
	mat.set_shader_parameter("corner_radius", radius)
	mat.set_shader_parameter("shimmer_offset", -0.5)
	bar.material = mat
	_materials.append(mat)
	return bar

func _apply_theme() -> void:
	_bar_color = ThemeManager.get_color("button_hover")
	for child in get_children():
		if child is HBoxContainer:
			for sub in child.get_children():
				if sub is ColorRect:
					sub.color = _bar_color

func _on_reduce_motion_changed(enabled: bool) -> void:
	if enabled:
		set_process(false)
	else:
		set_process(visible and not Config.get_reduced_motion())

func reset_shimmer() -> void:
	_shimmer_offset = -0.5
	for mat in _materials:
		mat.set_shader_parameter("shimmer_offset", -0.5)
	set_process(visible and not Config.get_reduced_motion())
