extends RefCounted
## Handles context menu, action bar callbacks, and reaction picker
## for MessageView. Created and owned by the parent message_view.gd.

const ReactionPickerScene := preload(
	"res://scenes/messages/reaction_picker.tscn"
)

var _view: Control # parent MessageView
var _context_menu: PopupMenu
var _context_menu_data: Dictionary = {}
var _delete_dialog: ConfirmationDialog
var _pending_delete_id: String = ""
var _reaction_picker: Control = null


func _init(view: Control) -> void:
	_view = view


func setup_context_menu() -> void:
	_context_menu = PopupMenu.new()
	_context_menu.add_item("Reply", 0)
	_context_menu.add_item("Edit", 1)
	_context_menu.add_item("Delete", 2)
	_context_menu.add_item("Add Reaction", 3)
	_context_menu.add_item("Remove All Reactions", 4)
	_context_menu.add_item("Start Thread", 5)
	_context_menu.id_pressed.connect(on_context_menu_id_pressed)
	_view.add_child(_context_menu)


# --- Action Bar Callbacks ---

func on_bar_reply(msg_data: Dictionary) -> void:
	AppState.initiate_reply(msg_data.get("id", ""))
	_view._hover.hide_action_bar()


func on_bar_edit(msg_data: Dictionary) -> void:
	var msg_id: String = msg_data.get("id", "")
	AppState.start_editing(msg_id)
	var node: Control = _view._find_message_node(msg_id)
	if node:
		var mc = node.get("message_content")
		if mc:
			mc.enter_edit_mode(
				msg_id, msg_data.get("content", "")
			)
	_view._hover.hide_action_bar()


func on_bar_thread(msg_data: Dictionary) -> void:
	AppState.open_thread(msg_data.get("id", ""))
	_view._hover.hide_action_bar()


func on_bar_delete(msg_data: Dictionary) -> void:
	_pending_delete_id = msg_data.get("id", "")
	_view._hover.hide_action_bar()
	if not _delete_dialog:
		_delete_dialog = ConfirmationDialog.new()
		_delete_dialog.dialog_text = (
			"Are you sure you want to delete this message?"
		)
		_delete_dialog.confirmed.connect(on_delete_confirmed)
		_view.add_child(_delete_dialog)
	_delete_dialog.popup_centered()


func on_delete_confirmed() -> void:
	if not _pending_delete_id.is_empty():
		AppState.delete_message(_pending_delete_id)
		_pending_delete_id = ""


# --- Shared Context Menu ---

func on_context_menu_requested(
	pos: Vector2i, msg_data: Dictionary,
) -> void:
	_context_menu_data = msg_data
	var author: Dictionary = msg_data.get("author", {})
	var is_own: bool = (
		author.get("id", "")
		== Client.current_user.get("id", "")
	)
	var channel_id: String = msg_data.get("channel_id", "")
	var space_id: String = Client._channel_to_space.get(
		channel_id, ""
	)
	var can_manage: bool = Client.has_channel_permission(
		space_id, channel_id, AccordPermission.MANAGE_MESSAGES
	)
	_context_menu.set_item_disabled(
		1, not (is_own or can_manage)
	)
	_context_menu.set_item_disabled(
		2, not (is_own or can_manage)
	)
	var has_reactions: bool = (
		msg_data.get("reactions", []).size() > 0
	)
	_context_menu.set_item_disabled(
		4, not (can_manage and has_reactions)
	)
	_context_menu.hide()
	_context_menu.position = pos
	_context_menu.popup()


func on_context_menu_id_pressed(id: int) -> void:
	match id:
		0: # Reply
			AppState.initiate_reply(
				_context_menu_data.get("id", "")
			)
		1: # Edit
			var msg_id: String = _context_menu_data.get("id", "")
			AppState.start_editing(msg_id)
			var node: Control = _view._find_message_node(msg_id)
			if node:
				var mc = node.get("message_content")
				if mc:
					mc.enter_edit_mode(
						msg_id,
						_context_menu_data.get("content", ""),
					)
		2: # Delete
			_pending_delete_id = _context_menu_data.get("id", "")
			if not _delete_dialog:
				_delete_dialog = ConfirmationDialog.new()
				_delete_dialog.dialog_text = (
					"Are you sure you want to "
					+ "delete this message?"
				)
				_delete_dialog.confirmed.connect(
					on_delete_confirmed
				)
				_view.add_child(_delete_dialog)
			_delete_dialog.popup_centered()
		3: # Add Reaction
			open_reaction_picker(_context_menu_data)
		4: # Remove All Reactions
			var cid: String = _context_menu_data.get(
				"channel_id", ""
			)
			var mid: String = _context_menu_data.get("id", "")
			Client.remove_all_reactions(cid, mid)
		5: # Start Thread
			AppState.open_thread(
				_context_menu_data.get("id", "")
			)


func open_reaction_picker(msg_data: Dictionary) -> void:
	if _reaction_picker and is_instance_valid(_reaction_picker):
		_reaction_picker.queue_free()
	_reaction_picker = ReactionPickerScene.instantiate()
	_view.get_tree().root.add_child(_reaction_picker)
	var channel_id: String = msg_data.get("channel_id", "")
	var msg_id: String = msg_data.get("id", "")
	var pos := _view.get_global_mouse_position()
	_reaction_picker.open(channel_id, msg_id, pos)
	_reaction_picker.closed.connect(func():
		_reaction_picker = null
	)
