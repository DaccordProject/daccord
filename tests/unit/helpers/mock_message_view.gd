extends Control
## Minimal mock of MessageView for testing MessageViewScroll.

var scroll_container: ScrollContainer
var virtual_content: Control
var _virtual: MockVirtual


func _init() -> void:
	_virtual = MockVirtual.new()


class MockVirtual extends RefCounted:
	var _last_row_node: Control = null

	func get_last_row_node() -> Control:
		return _last_row_node

	func row_count() -> int:
		return 0

	func update_visible_rows(_scroll_value: float) -> void:
		pass
