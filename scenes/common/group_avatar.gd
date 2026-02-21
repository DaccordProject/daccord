extends ColorRect

const AvatarScene := preload("res://scenes/common/avatar.tscn")
const AvatarShader := preload("res://assets/theme/avatar_circle.gdshader")

@export var avatar_size: int = 32

@onready var grid: GridContainer = $Grid

func _ready() -> void:
	custom_minimum_size = Vector2(avatar_size, avatar_size)
	size = Vector2(avatar_size, avatar_size)
	color = Color(0.184, 0.192, 0.212)
	clip_children = CLIP_CHILDREN_ONLY

	var mat := ShaderMaterial.new()
	mat.shader = AvatarShader
	mat.set_shader_parameter("radius", 0.5)
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
		av.set_avatar_color(
			r.get("color", Color(0.345, 0.396, 0.949))
		)
		var dn: String = r.get("display_name", "")
		if dn.length() > 0:
			av.set_letter(dn[0].to_upper())
		else:
			av.set_letter("")
		var avatar_url = r.get("avatar", null)
		if avatar_url is String and not avatar_url.is_empty():
			av.set_avatar_url(avatar_url)
