extends GutTest

var _ScrollScript: GDScript


func before_all() -> void:
	_ScrollScript = load("res://scenes/messages/message_view_scroll.gd")


# --- _old_message_count ---

func test_old_message_count_initial_value() -> void:
	var view := Control.new()
	add_child(view)
	var scroll = _ScrollScript.new(view)
	assert_eq(scroll._old_message_count, 0)
	view.queue_free()


func test_old_message_count_is_int() -> void:
	var view := Control.new()
	add_child(view)
	var scroll = _ScrollScript.new(view)
	assert_typeof(scroll._old_message_count, TYPE_INT)
	view.queue_free()


func test_old_message_count_set_and_read() -> void:
	var view := Control.new()
	add_child(view)
	var scroll = _ScrollScript.new(view)
	scroll._old_message_count = 5
	assert_eq(scroll._old_message_count, 5)
	view.queue_free()


func test_old_message_count_survives_reassignment() -> void:
	var view := Control.new()
	add_child(view)
	var scroll = _ScrollScript.new(view)
	scroll._old_message_count = 10
	scroll._old_message_count = 25
	assert_eq(scroll._old_message_count, 25)
	view.queue_free()


# --- auto_scroll ---

func test_auto_scroll_default_true() -> void:
	var view := Control.new()
	add_child(view)
	var scroll = _ScrollScript.new(view)
	assert_true(scroll.auto_scroll)
	view.queue_free()


# --- is_loading_older ---

func test_is_loading_older_default_false() -> void:
	var view := Control.new()
	add_child(view)
	var scroll = _ScrollScript.new(view)
	assert_false(scroll.is_loading_older)
	view.queue_free()


# --- get_last_message_child ---

func test_get_last_message_child_returns_null_when_empty() -> void:
	var mock_script: GDScript = load("res://tests/unit/helpers/mock_message_view.gd")
	var mock_view = mock_script.new()
	var sc := ScrollContainer.new()
	var ml := VBoxContainer.new()
	sc.add_child(ml)
	mock_view.scroll_container = sc
	mock_view.message_list = ml
	mock_view.add_child(sc)
	add_child(mock_view)
	await get_tree().process_frame
	var scroll = _ScrollScript.new(mock_view)
	var result: Control = scroll.get_last_message_child()
	assert_null(result)
	mock_view.queue_free()


func test_get_last_message_child_returns_last_child() -> void:
	var mock_script: GDScript = load("res://tests/unit/helpers/mock_message_view.gd")
	var mock_view = mock_script.new()
	var sc := ScrollContainer.new()
	var ml := VBoxContainer.new()
	sc.add_child(ml)
	mock_view.scroll_container = sc
	mock_view.message_list = ml
	mock_view.add_child(sc)
	add_child(mock_view)
	var child1 := Control.new()
	var child2 := Control.new()
	ml.add_child(child1)
	ml.add_child(child2)
	await get_tree().process_frame
	var scroll = _ScrollScript.new(mock_view)
	var result: Control = scroll.get_last_message_child()
	assert_eq(result, child2)
	mock_view.queue_free()
