extends ColorRect

var _version_info: Dictionary = {}
var _total_size: int = 0

@onready var _title_label: Label = $CenterContainer/Panel/VBox/Header/Title
@onready var _close_btn: Button = $CenterContainer/Panel/VBox/Header/CloseButton
@onready var _status_label: Label = $CenterContainer/Panel/VBox/StatusLabel
@onready var _progress_bar: ProgressBar = $CenterContainer/Panel/VBox/ProgressBar
@onready var _size_label: Label = $CenterContainer/Panel/VBox/SizeLabel
@onready var _error_label: Label = $CenterContainer/Panel/VBox/ErrorLabel
@onready var _button_row: HBoxContainer = $CenterContainer/Panel/VBox/ButtonRow
@onready var _cancel_btn: Button = $CenterContainer/Panel/VBox/ButtonRow/CancelButton
@onready var _retry_btn: Button = $CenterContainer/Panel/VBox/ButtonRow/RetryButton
@onready var _restart_btn: Button = $CenterContainer/Panel/VBox/ButtonRow/RestartButton
@onready var _later_btn: Button = $CenterContainer/Panel/VBox/ButtonRow/LaterButton

func _ready() -> void:
	_close_btn.pressed.connect(_close)
	_cancel_btn.pressed.connect(_on_cancel)
	_retry_btn.pressed.connect(_on_retry)
	_restart_btn.pressed.connect(_on_restart)
	_later_btn.pressed.connect(_close)

	AppState.update_download_progress.connect(_on_progress)
	AppState.update_download_complete.connect(_on_complete)
	AppState.update_download_failed.connect(_on_failed)

	_set_downloading_state()

func setup(version_info: Dictionary) -> void:
	_version_info = version_info
	_total_size = version_info.get("download_size", 0)
	var version: String = version_info.get("version", "unknown")
	_status_label.text = "Downloading daccord v%s..." % version

func _set_downloading_state() -> void:
	_progress_bar.visible = true
	_size_label.visible = true
	_error_label.visible = false
	_cancel_btn.visible = true
	_retry_btn.visible = false
	_restart_btn.visible = false
	_later_btn.visible = false
	_progress_bar.value = 0

func _on_progress(percent: float) -> void:
	_progress_bar.value = percent
	if _total_size > 0:
		var downloaded: int = int(percent / 100.0 * _total_size)
		_size_label.text = "%s / %s" % [
			_format_size(downloaded), _format_size(_total_size)
		]
	else:
		_size_label.text = "%.0f%%" % percent

func _on_complete(_path: String) -> void:
	_status_label.text = "Download complete. Restart to apply the update."
	_progress_bar.value = 100
	_progress_bar.visible = false
	_size_label.visible = false
	_cancel_btn.visible = false
	_retry_btn.visible = false
	_restart_btn.visible = true
	_later_btn.visible = true

func _on_failed(error: String) -> void:
	_error_label.text = error
	_error_label.visible = true
	_progress_bar.visible = false
	_size_label.visible = false
	_cancel_btn.visible = false
	_retry_btn.visible = true
	_restart_btn.visible = false
	_later_btn.visible = false
	_status_label.text = "Download failed"

func _on_cancel() -> void:
	Updater.cancel_download()
	_close()

func _on_retry() -> void:
	_set_downloading_state()
	var version: String = _version_info.get("version", "unknown")
	_status_label.text = "Downloading daccord v%s..." % version
	Updater.download_update(_version_info)

func _on_restart() -> void:
	Updater.apply_update_and_restart()

func _close() -> void:
	AppState.update_download_progress.disconnect(_on_progress)
	AppState.update_download_complete.disconnect(_on_complete)
	AppState.update_download_failed.disconnect(_on_failed)
	queue_free()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()

static func _format_size(bytes: int) -> String:
	if bytes < 1024:
		return str(bytes) + " B"
	if bytes < 1024 * 1024:
		return str(snappedi(bytes / 1024, 1)) + " KB"
	return "%.1f MB" % (bytes / 1048576.0)
