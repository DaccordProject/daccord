@tool
extends EditorPlugin


func _enter_tree() -> void:
	add_custom_type(
		"AccordClient",
		"Node",
		preload("res://addons/accordkit/core/accord_client.gd"),
		null
	)


func _exit_tree() -> void:
	remove_custom_type("AccordClient")
