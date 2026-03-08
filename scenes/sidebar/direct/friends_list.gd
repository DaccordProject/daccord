extends VBoxContainer

## Friends list panel shown in the DM sidebar when Friends tab is active.
## Displays All / Online / Pending / Blocked filter tabs and friend rows.

signal dm_opened(channel_id: String)

const FriendItemScene := preload("res://scenes/sidebar/direct/friend_item.tscn")
const ConfirmDialogScene := preload("res://scenes/admin/confirm_dialog.tscn")
const AddFriendDialogScene := preload("res://scenes/sidebar/direct/add_friend_dialog.tscn")

# Filter tab indices
const TAB_ALL := 0
const TAB_ONLINE := 1
const TAB_PENDING := 2
const TAB_BLOCKED := 3

var _current_tab: int = TAB_ALL

@onready var tab_bar: HBoxContainer = $TabBar
@onready var all_btn: Button = $TabBar/AllBtn
@onready var online_btn: Button = $TabBar/OnlineBtn
@onready var pending_btn: Button = $TabBar/PendingBtn
@onready var pending_badge: Label = $TabBar/PendingBtn/PendingBadge
@onready var blocked_btn: Button = $TabBar/BlockedBtn
@onready var add_friend_btn: Button = $TabBar/AddFriendBtn
@onready var scroll: ScrollContainer = $ScrollContainer
@onready var list_vbox: VBoxContainer = $ScrollContainer/ListVBox
@onready var empty_label: Label = $EmptyLabel

func _ready() -> void:
	add_to_group("themed")
	all_btn.pressed.connect(func(): _set_tab(TAB_ALL))
	online_btn.pressed.connect(func(): _set_tab(TAB_ONLINE))
	pending_btn.pressed.connect(func(): _set_tab(TAB_PENDING))
	blocked_btn.pressed.connect(func(): _set_tab(TAB_BLOCKED))
	add_friend_btn.pressed.connect(_on_add_friend_pressed)
	AppState.relationships_updated.connect(_refresh)
	AppState.friend_request_received.connect(_on_friend_request_received)
	_refresh()

func _set_tab(tab: int) -> void:
	_current_tab = tab
	_refresh()
	_update_tab_highlights()

func _update_tab_highlights() -> void:
	for btn in [all_btn, online_btn, pending_btn, blocked_btn]:
		btn.remove_theme_color_override("font_color")
	var active_btn: Button
	match _current_tab:
		TAB_ALL: active_btn = all_btn
		TAB_ONLINE: active_btn = online_btn
		TAB_PENDING: active_btn = pending_btn
		TAB_BLOCKED: active_btn = blocked_btn
	if active_btn:
		active_btn.add_theme_color_override(
			"font_color", ThemeManager.get_color("accent")
		)

func _refresh() -> void:
	for child in list_vbox.get_children():
		child.queue_free()

	# Update pending badge
	var pending_count: int = Client.relationships.get_pending_incoming().size()
	pending_badge.text = str(pending_count)
	pending_badge.visible = pending_count > 0

	var rels: Array = _get_filtered_rels()
	empty_label.visible = rels.is_empty()
	scroll.visible = not rels.is_empty()

	for rel in rels:
		var item: HBoxContainer = FriendItemScene.instantiate()
		list_vbox.add_child(item)
		item.setup(rel)
		var user_id: String = rel["user"].get("id", "")
		item.message_pressed.connect(_on_message_pressed)
		item.remove_pressed.connect(_on_remove_pressed)
		item.block_pressed.connect(_on_block_pressed)
		item.accept_pressed.connect(_on_accept_pressed)
		item.decline_pressed.connect(_on_decline_pressed)
		item.cancel_pressed.connect(_on_cancel_pressed)
		item.unblock_pressed.connect(_on_unblock_pressed)

func _get_filtered_rels() -> Array:
	match _current_tab:
		TAB_ALL:
			return Client.relationships.get_friends()
		TAB_ONLINE:
			return Client.relationships.get_friends().filter(func(r):
				return r["user"].get("status", ClientModels.UserStatus.OFFLINE) \
					!= ClientModels.UserStatus.OFFLINE
			)
		TAB_PENDING:
			var incoming: Array = Client.relationships.get_pending_incoming()
			var outgoing: Array = Client.relationships.get_pending_outgoing()
			return incoming + outgoing
		TAB_BLOCKED:
			return Client.relationships.get_blocked()
	return []

func _on_add_friend_pressed() -> void:
	var dialog := AddFriendDialogScene.instantiate()
	get_tree().root.add_child(dialog)

func _on_friend_request_received(_user_id: String) -> void:
	# Switch to Pending tab so the user sees the new request
	_set_tab(TAB_PENDING)

func _on_message_pressed(user_id: String) -> void:
	Client.create_dm(user_id)

func _on_remove_pressed(user_id: String) -> void:
	var dname: String = _display_name_for(user_id)
	var dialog := ConfirmDialogScene.instantiate()
	get_tree().root.add_child(dialog)
	dialog.setup(
		"Remove Friend",
		"Remove %s from your friends?" % dname,
		"Remove",
		true
	)
	dialog.confirmed.connect(func(): Client.relationships.remove_friend(user_id))

func _on_block_pressed(user_id: String) -> void:
	Client.relationships.block_user(user_id)

func _on_accept_pressed(user_id: String) -> void:
	Client.relationships.accept_friend_request(user_id)

func _on_decline_pressed(user_id: String) -> void:
	Client.relationships.decline_friend_request(user_id)

func _on_cancel_pressed(user_id: String) -> void:
	Client.relationships.decline_friend_request(user_id)

func _on_unblock_pressed(user_id: String) -> void:
	Client.relationships.unblock_user(user_id)

func _display_name_for(user_id: String) -> String:
	var rel = Client.relationships.get_relationship(user_id)
	if rel != null:
		return rel["user"].get("display_name", "this user")
	return "this user"
