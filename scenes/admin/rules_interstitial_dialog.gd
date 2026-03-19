extends ModalBase

## Interstitial dialog shown when a user enters a space that has a
## rules_channel_id set and they have not yet accepted the rules.
## Fetches messages from the rules channel and displays them. On accept,
## stores acknowledgement in Config.

signal rules_accepted()

var _space_id: String = ""
var _rules_channel_id: String = ""

@onready var _content_label: RichTextLabel = %ContentLabel
@onready var _accept_btn: Button = %AcceptButton
@onready var _close_btn: Button = %CloseButton


func setup(space_id: String, rules_channel_id: String) -> void:
	_space_id = space_id
	_rules_channel_id = rules_channel_id


func _ready() -> void:
	_bind_modal_nodes($CenterContainer/Panel, 520.0)
	_close_btn.pressed.connect(_close)

	# Style accept button with accent color
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = ThemeManager.get_color("accent")
	btn_style.set_corner_radius_all(4)
	btn_style.content_margin_left = 12.0
	btn_style.content_margin_right = 12.0
	btn_style.content_margin_top = 4.0
	btn_style.content_margin_bottom = 4.0
	_accept_btn.add_theme_stylebox_override("normal", btn_style)
	_accept_btn.pressed.connect(_on_accept)

	_fetch_rules.call_deferred()


func _fetch_rules() -> void:
	if _rules_channel_id.is_empty():
		_content_label.text = "No rules channel configured."
		return

	# Try cached messages first, then fetch via REST
	var cached: Array = Client.get_messages_for_channel(_rules_channel_id)
	if not cached.is_empty():
		_render_messages(cached)
		return

	var client: AccordClient = Client._client_for_space(_space_id)
	if client == null:
		_content_label.text = "Unable to load rules."
		return
	var result: RestResult = await client.messages.list(
		_rules_channel_id, {"limit": 50}
	)
	if not result.ok or not result.data is Array:
		_content_label.text = "Failed to load rules."
		return

	var msgs: Array = []
	for msg in result.data:
		if msg is AccordMessage:
			msgs.append({"content": msg.content})
	msgs.reverse()
	_render_messages(msgs)


func _render_messages(messages: Array) -> void:
	if messages.is_empty():
		_content_label.text = "No rules have been posted yet."
		return
	var combined: String = ""
	for msg in messages:
		var content: String = ""
		if msg is Dictionary:
			content = msg.get("content", "")
		if not content.is_empty():
			combined += ClientModels.markdown_to_bbcode(content) + "\n\n"
	_content_label.text = combined.strip_edges()


func _on_accept() -> void:
	Config.set_rules_accepted(_space_id)
	rules_accepted.emit()
	_close()
