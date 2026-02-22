extends RefCounted
## Scroll management for MessageView.
## Handles auto-scroll, scroll animation, and loading older messages.

var auto_scroll: bool = true
var is_loading_older: bool = false

var _view: Control # parent MessageView
var _scroll_tween: Tween
var _old_message_count: int = 0


func _init(view: Control) -> void:
	_view = view


func scroll_to_bottom() -> void:
	var sc: ScrollContainer = _view.scroll_container
	sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value)


func scroll_to_bottom_animated() -> void:
	var sc: ScrollContainer = _view.scroll_container
	var target := int(sc.get_v_scroll_bar().max_value)
	if Config.get_reduced_motion():
		sc.scroll_vertical = target
		return
	var distance := absi(target - sc.scroll_vertical)
	if distance < 50:
		sc.scroll_vertical = target
		return
	if _scroll_tween and _scroll_tween.is_valid():
		_scroll_tween.kill()
	_scroll_tween = _view.create_tween()
	_scroll_tween.tween_property(sc, "scroll_vertical", target, 0.2) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func get_last_message_child() -> Control:
	var children: Array[Node] = _view.message_list.get_children()
	for i in range(children.size() - 1, -1, -1):
		var child: Node = children[i]
		if not _view._is_persistent_node(child):
			return child as Control
	return null


func on_scrollbar_changed() -> void:
	if auto_scroll:
		scroll_to_bottom()


func on_scroll_value_changed(value: float) -> void:
	var scrollbar: VScrollBar = _view.scroll_container.get_v_scroll_bar()
	auto_scroll = value >= scrollbar.max_value - scrollbar.page - 10


func on_older_messages_pressed() -> void:
	if is_loading_older or _view.current_channel_id.is_empty():
		return
	is_loading_older = true
	auto_scroll = false
	_view.older_btn.text = "Loading..."
	_view.older_btn.disabled = true
	var count_before: int = Client.get_messages_for_channel(
		_view.current_channel_id
	).size()
	# Save scroll height before loading
	var sc: ScrollContainer = _view.scroll_container
	var prev_scroll_max := sc.get_v_scroll_bar().max_value
	var prev_scroll_val := sc.scroll_vertical
	Client.fetch.fetch_older_messages(_view.current_channel_id)
	# Wait for re-render triggered by messages_updated
	await AppState.messages_updated
	# Restore scroll position so it doesn't jump
	await _view.get_tree().process_frame
	var new_scroll_max := sc.get_v_scroll_bar().max_value
	var diff := new_scroll_max - prev_scroll_max
	sc.scroll_vertical = prev_scroll_val + int(diff)
	# Hide button if fewer than MESSAGE_CAP were loaded (no more history)
	var count_after: int = Client.get_messages_for_channel(
		_view.current_channel_id
	).size()
	var loaded := count_after - count_before
	if loaded < Client.MESSAGE_CAP:
		_view.older_btn.visible = false
	_view.older_btn.text = "Show older messages"
	_view.older_btn.disabled = false
	is_loading_older = false
