extends ColorRect

const AvatarScene := preload("res://scenes/common/avatar.tscn")
const AvatarShader := preload("res://assets/theme/avatar_circle.gdshader")

@export var avatar_size: int = 32

@onready var grid: GridContainer = $Grid

func _ready() -> void:
	add_to_group("themed")
	custom_minimum_size = Vector2(avatar_size, avatar_size)
	size = Vector2(avatar_size, avatar_size)
	color = ThemeManager.get_color("modal_bg")
	clip_children = CLIP_CHILDREN_ONLY

func _apply_theme() -> void:
	color = ThemeManager.get_color("modal_bg")

	var mat := ShaderMaterial.new()
	mat.shader = AvatarShader
	mat.set_shader_parameter("radius", 0.5)
	mat.set_shader_parameter(
		"ring_color", ThemeManager.get_color("status_online")
	)
	material = mat

	grid.columns = 2
	grid.set_anchors_preset(PRESET_FULL_RECT)
	grid.add_theme_constant_override("h_separation", 1)
	grid.add_theme_constant_override("v_separation", 1)

func setup_recipients(recipients: Array) -> void:
	for child in grid.get_children():
		child.queue_free()

	var mini_size: int = (avatar_size - 1) / 2
	var count: int = mini(recipients.size(), 4)

	for i in count:
		var r: Dictionary = recipients[i]
		var av: ColorRect = AvatarScene.instantiate()
		av.avatar_size = mini_size
		av.show_letter = true
		av.letter_font_size = 8
		grid.add_child(av)
		av.custom_minimum_size = Vector2(mini_size, mini_size)
		av.size = Vector2(mini_size, mini_size)
		av.setup_from_dict(r)
