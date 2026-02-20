extends VBoxContainer

const SHIMMER_SHADER := preload("res://theme/skeleton_shimmer.gdshader")

const BAR_COLOR := Color(0.24, 0.25, 0.27)
const ROW_COUNT := 5
const SHIMMER_DURATION := 1.2

var _shimmer_offset: float = -0.5
var _materials: Array[ShaderMaterial] = []

# Per-row layout variation: [author_width, content1_width, content2_width (0 = none)]
var _row_configs: Array = [
	[110, 300, 180],
	[90, 260, 0],
	[130, 320, 200],
	[100, 280, 0],
	[140, 240, 160],
]

func _ready() -> void:
	for i in ROW_COUNT:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		add_child(row)

		# Avatar placeholder (42x42 circle)
		var avatar := _make_bar(42, 42, 0.5)
		row.add_child(avatar)

		# Text bars column
		var text_col := VBoxContainer.new()
		text_col.add_theme_constant_override("separation", 6)
		text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text_col)

		var cfg: Array = _row_configs[i]

		# Author bar
		var author_bar := _make_bar(int(cfg[0]), 14, 0.1)
		text_col.add_child(author_bar)

		# Content bar 1
		var content1 := _make_bar(int(cfg[1]), 14, 0.1)
		text_col.add_child(content1)

		# Content bar 2 (optional)
		if int(cfg[2]) > 0:
			var content2 := _make_bar(int(cfg[2]), 14, 0.1)
			text_col.add_child(content2)

	if Config.get_reduced_motion():
		set_process(false)

func _process(delta: float) -> void:
	_shimmer_offset += delta / SHIMMER_DURATION
	if _shimmer_offset > 1.5:
		_shimmer_offset = -0.5
	for mat in _materials:
		mat.set_shader_parameter("shimmer_offset", _shimmer_offset)

func _make_bar(w: int, h: int, radius: float) -> ColorRect:
	var bar := ColorRect.new()
	bar.custom_minimum_size = Vector2(w, h)
	bar.color = BAR_COLOR
	var mat := ShaderMaterial.new()
	mat.shader = SHIMMER_SHADER
	mat.set_shader_parameter("corner_radius", radius)
	mat.set_shader_parameter("shimmer_offset", -0.5)
	bar.material = mat
	_materials.append(mat)
	return bar

func reset_shimmer() -> void:
	_shimmer_offset = -0.5
	for mat in _materials:
		mat.set_shader_parameter("shimmer_offset", -0.5)
	set_process(visible and not Config.get_reduced_motion())
