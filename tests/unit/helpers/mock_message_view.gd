extends Control
## Minimal mock of MessageView for testing MessageViewScroll.

var scroll_container: ScrollContainer
var message_list: VBoxContainer


func _is_persistent_node(_child: Node) -> bool:
	return false
