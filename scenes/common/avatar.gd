extends ColorRect

@export var avatar_size: int = 32
@export var show_letter: bool = false
@export var letter_font_size: int = 14

var _shader_material: ShaderMaterial

@onready var letter_label: Label = $LetterLabel

func _ready() -> void:
	custom_minimum_size = Vector2(avatar_size, avatar_size)
	var AvatarShader := preload("res://theme/avatar_circle.gdshader")
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = AvatarShader
	_shader_material.set_shader_parameter("radius", 0.5)
	material = _shader_material
	letter_label.visible = show_letter
	letter_label.add_theme_font_size_override("font_size", letter_font_size)
	_resize_letter_label()

func set_avatar_color(c: Color) -> void:
	color = c

func set_letter(text: String) -> void:
	letter_label.text = text
	letter_label.visible = show_letter and text != ""

func set_radius(value: float) -> void:
	if _shader_material:
		_shader_material.set_shader_parameter("radius", value)

func tween_radius(from: float, to: float, duration: float = 0.15) -> Tween:
	if _shader_material:
		var tw := create_tween()
		tw.tween_method(set_radius, from, to, duration)
		return tw
	return null

func _resize_letter_label() -> void:
	letter_label.offset_right = avatar_size
	letter_label.offset_bottom = avatar_size
