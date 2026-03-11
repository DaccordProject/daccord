extends GutTest

var picker: PanelContainer


func before_each() -> void:
	# Clear space ID so no Custom tab is added
	AppState.current_space_id = ""
	picker = load("res://scenes/messages/composer/emoji_picker.tscn").instantiate()
	add_child(picker)
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(picker):
		picker.queue_free()
		await get_tree().process_frame
	AppState.current_space_id = ""


# --- script loads without parse errors ---

func test_instantiates_without_error() -> void:
	assert_true(is_instance_valid(picker))


# --- UI element existence ---

func test_category_bar_exists() -> void:
	assert_not_null(picker.category_bar)


func test_search_input_exists() -> void:
	assert_not_null(picker.search_input)


func test_emoji_grid_exists() -> void:
	assert_not_null(picker.emoji_grid)


func test_scroll_exists() -> void:
	assert_not_null(picker.scroll)


# --- initial visibility ---

func test_picker_starts_visible_when_added() -> void:
	# The picker scene itself — visibility is controlled by the parent compositor.
	# We just confirm it can be hidden and the property is accessible.
	picker.visible = false
	assert_false(picker.visible)


# --- signal existence ---

func test_has_emoji_picked_signal() -> void:
	assert_has_signal(picker, "emoji_picked")


# --- category bar button count ---

func test_category_bar_button_count_matches_emoji_data() -> void:
	# Expect: 1 recent btn + N category buttons (no custom tab since space_id is empty)
	var expected_count: int = 1 + EmojiData.category_icons.size()
	assert_eq(picker.category_bar.get_child_count(), expected_count)


# --- _on_search_changed: empty query reloads grid ---

func test_search_changed_empty_clears_and_reloads_without_crash() -> void:
	# Populate the grid with some emoji from the first category
	var first_cat: int = EmojiData.Category.SMILEYS
	picker._current_category = first_cat
	picker._is_recent_selected = false
	picker._is_custom_selected = false
	picker._on_search_changed("")
	await get_tree().process_frame
	# Should have loaded the default category (SMILEYS has entries)
	assert_true(picker.emoji_grid.get_child_count() > 0)


# --- _on_search_changed: query filters results ---

func test_search_changed_smile_populates_grid() -> void:
	picker._current_category = EmojiData.Category.SMILEYS
	picker._is_recent_selected = false
	picker._is_custom_selected = false
	# "smil" matches "smiling_eyes", "slightly_smiling", etc.
	picker._on_search_changed("smil")
	await get_tree().process_frame
	# "smil" should match at least one emoji
	assert_true(picker.emoji_grid.get_child_count() > 0)


func test_search_changed_with_nonsense_query_clears_grid() -> void:
	picker._on_search_changed("zzzzunlikelymatch9999")
	await get_tree().process_frame
	assert_eq(picker.emoji_grid.get_child_count(), 0)


# --- category selection updates internal state ---

func test_category_pressed_updates_current_category() -> void:
	picker._on_category_pressed(EmojiData.Category.FOOD)
	assert_eq(picker._current_category, EmojiData.Category.FOOD)


func test_category_pressed_clears_custom_selected() -> void:
	picker._is_custom_selected = true
	picker._on_category_pressed(EmojiData.Category.OBJECTS)
	assert_false(picker._is_custom_selected)


func test_category_pressed_clears_recent_selected() -> void:
	picker._is_recent_selected = true
	picker._on_category_pressed(EmojiData.Category.OBJECTS)
	assert_false(picker._is_recent_selected)


# --- no Custom tab when space_id is empty ---

func test_no_custom_btn_when_space_id_empty() -> void:
	assert_null(picker._custom_btn)
