extends PanelContainer

const UpdateDownloadDialogScene := preload(
	"res://scenes/messages/update_download_dialog.tscn"
)

var _version_info: Dictionary = {}

@onready var version_label: Label = $HBox/VersionLabel
@onready var view_changes_button: Button = $HBox/ViewChangesButton
@onready var update_button: Button = $HBox/UpdateButton
@onready var skip_button: Button = $HBox/SkipButton
@onready var dismiss_button: Button = $HBox/DismissButton

func _ready() -> void:
	AppState.update_available.connect(_on_update_available)
	view_changes_button.pressed.connect(_on_view_changes)
	update_button.pressed.connect(_on_update)
	skip_button.pressed.connect(_on_skip)
	dismiss_button.pressed.connect(_on_dismiss)
	visible = false

func _on_update_available(info: Dictionary) -> void:
	_version_info = info
	var version: String = info.get("version", "unknown")
	version_label.text = "daccord v%s is available" % version
	visible = true

func _on_view_changes() -> void:
	var url: String = _version_info.get("release_url", "")
	if not url.is_empty():
		OS.shell_open(url)

func _on_update() -> void:
	var download_url: String = _version_info.get("download_url", "")
	# Linux with a download URL: show in-app download dialog
	if OS.get_name() == "Linux" and not download_url.is_empty():
		var dialog: ColorRect = UpdateDownloadDialogScene.instantiate()
		get_tree().root.add_child(dialog)
		dialog.setup(_version_info)
		Updater.download_update(_version_info)
		visible = false
		return
	# Fallback: open in browser
	var url: String = download_url
	if url.is_empty():
		url = _version_info.get("release_url", "")
	if not url.is_empty():
		OS.shell_open(url)

func _on_skip() -> void:
	var version: String = _version_info.get("version", "")
	if not version.is_empty():
		Updater.skip_version(version)
	visible = false

func _on_dismiss() -> void:
	var version: String = _version_info.get("version", "")
	if not version.is_empty():
		Updater.dismiss_version(version)
	visible = false
