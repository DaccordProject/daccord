class_name DialogHelper
extends RefCounted

## Helpers for instantiating and showing dialog scenes.


## Instantiates a dialog scene and adds it to the scene tree root.
## Returns the dialog node so callers can call setup() on it.
static func open(scene: PackedScene, tree: SceneTree) -> Node:
	var dialog := scene.instantiate()
	tree.root.add_child(dialog)
	return dialog


## Opens a ConfirmDialog with the given parameters and connects its
## confirmed signal to the provided callback.
static func confirm(scene: PackedScene, tree: SceneTree,
		title: String, message: String, confirm_text: String,
		danger: bool, callback: Callable) -> void:
	var dialog := scene.instantiate()
	tree.root.add_child(dialog)
	dialog.setup(title, message, confirm_text, danger)
	dialog.confirmed.connect(callback)
