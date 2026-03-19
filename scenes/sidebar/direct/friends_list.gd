extends VBoxContainer

## Friends list panel shown in the DM sidebar when Friends tab is active.
## Displays All / Online / Pending / Blocked filter tabs and friend rows.

signal dm_opened(channel_id: String)

const FriendItemScene := preload("res://scenes/sidebar/direct/friend_item.tscn")
const ConfirmDialogScene := preload("res://scenes/admin/confirm_dialog.tscn")
const AddFriendDialogScene := preload("res://scenes/sidebar/direct/add_friend_dialog.tscn")
const AddServerDialogScene := preload("res://scenes/sidebar/guild_bar/add_server_dialog.tscn")

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
@onready var count_label: Label = $CountLabel
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
	NodeUtils.free_children(list_vbox)

	# Update pending badge
	var pending_count: int = Client.relationships.get_pending_incoming().size()
	pending_badge.text = str(pending_count)
	pending_badge.visible = pending_count > 0

	var rels: Array = _get_filtered_rels()
	empty_label.visible = rels.is_empty()
	scroll.visible = not rels.is_empty()

	# FRND-14: Contextual empty state
	match _current_tab:
		TAB_ALL:
			empty_label.text = tr("No friends yet. Add someone!")
		TAB_ONLINE:
			empty_label.text = tr("No friends online.")
		TAB_PENDING:
			empty_label.text = tr("No pending requests.")
		TAB_BLOCKED:
			empty_label.text = tr("No blocked users.")

	# FRND-12: Count header
	var tab_name: String
	match _current_tab:
		TAB_ALL: tab_name = tr("ALL FRIENDS")
		TAB_ONLINE: tab_name = tr("ONLINE")
		TAB_PENDING: tab_name = tr("PENDING")
		TAB_BLOCKED: tab_name = tr("BLOCKED")
	count_label.text = "%s — %d" % [tab_name, rels.size()]
	count_label.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)

	# FRND-10 & FRND-11: Section labels for pending, alphabetical sort
	if _current_tab == TAB_PENDING:
		var incoming: Array = Client.relationships.get_pending_incoming()
		var outgoing: Array = Client.relationships.get_pending_outgoing()
		_sort_by_name(incoming)
		_sort_by_name(outgoing)
		if not incoming.is_empty():
			_add_section_label(tr("INCOMING"))
			for rel in incoming:
				_add_friend_item(rel)
		if not outgoing.is_empty():
			_add_section_label(tr("OUTGOING"))
			for rel in outgoing:
				_add_friend_item(rel)
	else:
		_sort_by_name(rels)
		for rel in rels:
			_add_friend_item(rel)

func _sort_by_name(arr: Array) -> void:
	arr.sort_custom(func(a, b):
		# Available friends sort before unavailable
		var a_avail: bool = a.get("available", true)
		var b_avail: bool = b.get("available", true)
		if a_avail != b_avail:
			return a_avail # true < false = available first
		var na: String = a["user"].get("display_name", "").to_lower()
		var nb: String = b["user"].get("display_name", "").to_lower()
		return na < nb
	)

func _add_section_label(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	ThemeManager.style_label(lbl, 11, "text_muted")
	lbl.add_theme_constant_override("margin_left", 8)
	list_vbox.add_child(lbl)

func _add_friend_item(rel: Dictionary) -> void:
	var item: HBoxContainer = FriendItemScene.instantiate()
	list_vbox.add_child(item)
	item.setup(rel)
	item.message_pressed.connect(_on_message_pressed)
	item.remove_pressed.connect(_on_remove_pressed)
	item.block_pressed.connect(_on_block_pressed)
	item.accept_pressed.connect(_on_accept_pressed)
	item.decline_pressed.connect(_on_decline_pressed)
	item.cancel_pressed.connect(_on_cancel_pressed)
	item.unblock_pressed.connect(_on_unblock_pressed)
	item.rejoin_pressed.connect(_on_rejoin_pressed)
	item.remove_local_pressed.connect(_on_remove_local_pressed)

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
	DialogHelper.open(AddFriendDialogScene, get_tree())

func _on_friend_request_received(_user_id: String) -> void:
	# Switch to Pending tab so the user sees the new request
	_set_tab(TAB_PENDING)

func _on_message_pressed(user_id: String) -> void:
	Client.create_dm(user_id)

func _on_remove_pressed(user_id: String) -> void:
	var dname: String = _display_name_for(user_id)
	DialogHelper.confirm(ConfirmDialogScene, get_tree(),
		tr("Remove Friend"),
		tr("Remove %s from your friends?") % dname,
		tr("Remove"), true, func(): Client.relationships.remove_friend(user_id)
	)

func _on_block_pressed(user_id: String) -> void:
	var dname: String = _display_name_for(user_id)
	DialogHelper.confirm(ConfirmDialogScene, get_tree(),
		tr("Block %s") % dname,
		tr("They won't be able to message you or send friend requests."),
		tr("Block"), true, func(): Client.relationships.block_user(user_id)
	)

func _on_accept_pressed(user_id: String) -> void:
	Client.relationships.accept_friend_request(user_id)

func _on_decline_pressed(user_id: String) -> void:
	Client.relationships.decline_friend_request(user_id)

func _on_cancel_pressed(user_id: String) -> void:
	Client.relationships.decline_friend_request(user_id)

func _on_unblock_pressed(user_id: String) -> void:
	Client.relationships.unblock_user(user_id)

func _on_rejoin_pressed(server_url: String, space_name: String) -> void:
	var prefill: String = server_url
	if not space_name.is_empty():
		prefill += "#" + space_name
	var dialog: Node = DialogHelper.open(AddServerDialogScene, get_tree())
	# open_prefilled must be called after _ready, and DialogHelper.open adds
	# to tree synchronously, so it's safe to call immediately.
	if dialog.has_method("open_prefilled"):
		dialog.open_prefilled(prefill)

func _on_remove_local_pressed(server_url: String, user_id: String) -> void:
	DialogHelper.confirm(ConfirmDialogScene, get_tree(),
		tr("Remove Friend"),
		tr("Remove this friend from your local friend book? This cannot be undone."),
		tr("Remove"), true, func():
			Client.relationships.remove_unavailable_friend(server_url, user_id)
	)

func _display_name_for(user_id: String) -> String:
	var rel = Client.relationships.get_relationship(user_id)
	if rel != null:
		return rel["user"].get("display_name", tr("this user"))
	return tr("this user")
