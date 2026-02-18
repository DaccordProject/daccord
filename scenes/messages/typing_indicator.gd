extends HBoxContainer

var dots: Array[Label]
var anim_time: float = 0.0

@onready var dot1: Label = $Dots/Dot1
@onready var dot2: Label = $Dots/Dot2
@onready var dot3: Label = $Dots/Dot3
@onready var text_label: Label = $Text

func _ready() -> void:
	dots = [dot1, dot2, dot3]
	text_label.add_theme_font_size_override("font_size", 12)
	text_label.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643))
	for d in dots:
		d.add_theme_font_size_override("font_size", 16)
	set_process(false)

func _process(delta: float) -> void:
	anim_time += delta
	for i in dots.size():
		var phase: float = anim_time * 3.0 - float(i) * 0.8
		var alpha: float = (sin(phase) + 1.0) * 0.5
		alpha = clamp(alpha, 0.3, 1.0)
		dots[i].modulate.a = alpha

func show_typing(username: String) -> void:
	text_label.text = username + " is typing..."
	visible = true
	anim_time = 0.0
	set_process(true)

func hide_typing() -> void:
	visible = false
	set_process(false)
