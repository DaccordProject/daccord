extends Node

const LOCK_FILE := "user://daccord.lock"
const HEARTBEAT_INTERVAL := 2.0
const HEARTBEAT_STALE_THRESHOLD := 5.0

var _heartbeat_timer: Timer


func _ready() -> void:
	if _another_instance_running():
		# Forward any --uri to the running instance via IPC file
		var uri := _get_cli_uri()
		if not uri.is_empty():
			var file := FileAccess.open("user://daccord.uri", FileAccess.WRITE)
			if file:
				file.store_string(uri)
				file.close()
		else:
			OS.alert("daccord is already running.", "daccord")
		get_tree().quit()
		return
	_write_lock()
	# Periodically re-write the lock file so other instances can detect us
	# via a recent modification time, even if PID checks fail.
	_heartbeat_timer = Timer.new()
	_heartbeat_timer.wait_time = HEARTBEAT_INTERVAL
	_heartbeat_timer.timeout.connect(_write_lock)
	add_child(_heartbeat_timer)
	_heartbeat_timer.start()


func _get_cli_uri() -> String:
	var args := OS.get_cmdline_args()
	for i in args.size():
		if args[i] == "--uri" and i + 1 < args.size():
			return args[i + 1]
		if args[i].begins_with("daccord://"):
			return args[i]
	return ""


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
	# Primary check: was the lock file recently updated by a heartbeat?
	var mtime := FileAccess.get_modified_time(LOCK_FILE)
	var now := int(Time.get_unix_time_from_system())
	if (now - mtime) < HEARTBEAT_STALE_THRESHOLD:
		return true
	# Fallback: direct process check for the brief window before heartbeat
	return _is_process_alive(pid)


func _is_process_alive(pid: int) -> bool:
	if OS.get_name() == "Windows":
		var output: Array = []
		OS.execute(
			"tasklist",
			PackedStringArray(["/FI", "PID eq %d" % pid, "/NH"]),
			output
		)
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
