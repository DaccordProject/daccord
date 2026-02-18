extends PanelContainer

@onready var title_label: Label = $VBox/Title
@onready var description_rtl: RichTextLabel = $VBox/Description
@onready var footer_label: Label = $VBox/Footer

func _ready() -> void:
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.add_theme_color_override("font_color", Color(1, 1, 1))
	footer_label.add_theme_font_size_override("font_size", 11)
	footer_label.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643))

func setup(data: Dictionary) -> void:
	if data.is_empty():
		visible = false
		return

	visible = true
	title_label.text = data.get("title", "")
	description_rtl.text = data.get("description", "")
	footer_label.text = data.get("footer", "")

	title_label.visible = !title_label.text.is_empty()
	footer_label.visible = !footer_label.text.is_empty()

	# Set left border color
	var embed_color: Color = data.get("color", Color(0.345, 0.396, 0.949))
	var style: StyleBoxFlat = get_theme_stylebox("panel").duplicate()
	style.border_color = embed_color
	add_theme_stylebox_override("panel", style)
