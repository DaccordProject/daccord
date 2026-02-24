extends Node

const LOCK_FILE := "user://daccord.lock"

func _ready() -> void:
	if _another_instance_running():
		OS.alert("daccord is already running.", "daccord")
		get_tree().quit()
		return
	_write_lock()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		_remove_lock()

func _another_instance_running() -> bool:
	if not FileAccess.file_exists(LOCK_FILE):
		return false
	var file := FileAccess.open(LOCK_FILE, FileAccess.READ)
	if file == null:
		return false
	var pid_str := file.get_as_text().strip_edges()
	file.close()
	if not pid_str.is_valid_int():
		return false
	var pid := pid_str.to_int()
	if pid == OS.get_process_id():
		return false
	return _is_process_alive(pid)

func _is_process_alive(pid: int) -> bool:
	if OS.get_name() == "Windows":
		var output: Array = []
		OS.execute("tasklist", PackedStringArray(["/FI", "PID eq %d" % pid, "/NH"]), output)
		if output.size() > 0:
			return str(output[0]).contains(str(pid))
		return false
	return OS.execute("kill", PackedStringArray(["-0", str(pid)])) == 0

func _write_lock() -> void:
	var file := FileAccess.open(LOCK_FILE, FileAccess.WRITE)
	if file:
		file.store_string(str(OS.get_process_id()))
		file.close()

func _remove_lock() -> void:
	if FileAccess.file_exists(LOCK_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LOCK_FILE))
