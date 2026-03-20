class_name GuestPrompt

## Shared utility for showing a registration prompt when a guest user
## clicks a grayed-out interactive element. Uses class_name so any script
## can call GuestPrompt.show_if_guest() without an autoload dependency.

const GuestPromptDialogScene := preload(
	"res://scenes/common/guest_prompt_dialog.tscn"
)
const AuthDialogScene := preload(
	"res://scenes/sidebar/guild_bar/auth_dialog.tscn"
)

## Returns true if the user is in guest mode (and shows the prompt).
## Call at the top of any interactive handler to gate it:
##   if GuestPrompt.show_if_guest(): return
static func show_if_guest() -> bool:
	if not AppState.is_guest_mode:
		return false
	_show_prompt()
	return true

static func _show_prompt() -> void:
	var root: Window = Engine.get_main_loop().root
	# Prevent duplicate prompts
	for child in root.get_children():
		if child.is_in_group("guest_prompt"):
			return
	var dialog: ColorRect = GuestPromptDialogScene.instantiate()
	dialog.add_to_group("guest_prompt")
	root.add_child(dialog)

static func _open_auth_dialog() -> void:
	var base_url := AppState.guest_base_url
	if base_url.is_empty():
		return
	var root: Window = Engine.get_main_loop().root
	var auth_dialog := AuthDialogScene.instantiate()
	auth_dialog.setup(base_url)
	auth_dialog.auth_completed.connect(
		func(resolved_url: String, t: String, u: String, _p: String, dn: String):
			# Determine space_name from current space
			var space_name := "general"
			if not AppState.current_space_id.is_empty():
				var space: Dictionary = Client.get_space_by_id(
					AppState.current_space_id
				)
				if not space.is_empty():
					space_name = space.get("name", "general")
			Client.upgrade_guest_connection(
				resolved_url, t, space_name, u, dn,
			)
	)
	root.add_child(auth_dialog)
