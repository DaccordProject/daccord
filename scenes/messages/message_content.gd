extends VBoxContainer

var _edit_input: TextEdit = null
var _editing_message_id: String = ""

@onready var text_content: RichTextLabel = $TextContent
@onready var embed: PanelContainer = $Embed
@onready var reaction_bar: FlowContainer = $ReactionBar

func setup(data: Dictionary) -> void:
	var raw_text: String = data.get("content", "")
	var is_system: bool = data.get("system", false)

	if is_system:
		text_content.text = "[i][color=#8a8e94]" + raw_text + "[/color][/i]"
	else:
		text_content.text = ClientModels.markdown_to_bbcode(raw_text)

	var embed_data: Dictionary = data.get("embed", {})
	embed.setup(embed_data)

	var reactions: Array = data.get("reactions", [])
	reaction_bar.setup(reactions)

func enter_edit_mode(message_id: String, content: String) -> void:
	_editing_message_id = message_id
	text_content.visible = false
	_edit_input = TextEdit.new()
	_edit_input.text = content
	_edit_input.custom_minimum_size = Vector2(0, 36)
	_edit_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_edit_input.scroll_fit_content_height = true
	_edit_input.gui_input.connect(_on_edit_input)
	add_child(_edit_input)
	move_child(_edit_input, 0)
	_edit_input.grab_focus()

func _exit_edit_mode() -> void:
	if _edit_input:
		_edit_input.queue_free()
		_edit_input = null
	text_content.visible = true
	_editing_message_id = ""

func _on_edit_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER and not event.shift_pressed:
			var new_text := _edit_input.text.strip_edges()
			if not new_text.is_empty():
				AppState.edit_message(_editing_message_id, new_text)
			_exit_edit_mode()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			_exit_edit_mode()
			get_viewport().set_input_as_handled()
