extends Node

## Auto-update system: semver utilities, GitHub Releases API checks,
## periodic timer, and version dismiss/skip logic.

const GITHUB_RELEASES_URL := (
	"https://api.github.com/repos/DaccordProject/daccord/releases/latest"
)
const CHECK_INTERVAL_SEC := 3600 # 1 hour
const STARTUP_DELAY_SEC := 5.0

var _check_in_progress: bool = false
var _dismissed_version: String = ""
var _latest_version_info: Dictionary = {}
var _periodic_timer: Timer

# Download state
var _download_http: HTTPRequest = null
var _downloading: bool = false
var _download_version: String = ""
var _download_path: String = ""
var _update_ready: bool = false
var _staged_binary_path: String = ""


func _ready() -> void:
	_periodic_timer = Timer.new()
	_periodic_timer.wait_time = CHECK_INTERVAL_SEC
	_periodic_timer.one_shot = false
	_periodic_timer.timeout.connect(func(): check_for_updates(false))
	add_child(_periodic_timer)

	if not Config.get_auto_update_check():
		return

	if Config.has_servers():
		# Wait for first guild data before checking
		AppState.guilds_updated.connect(
			_on_first_guilds_updated, CONNECT_ONE_SHOT
		)
	else:
		# No servers configured -- check after a short delay
		var delay := get_tree().create_timer(STARTUP_DELAY_SEC)
		delay.timeout.connect(func(): check_for_updates(false))


func _on_first_guilds_updated() -> void:
	check_for_updates(false)


func check_for_updates(manual: bool) -> void:
	if _check_in_progress:
		return

	# Throttle passive checks to once per hour
	if not manual:
		var now: int = int(Time.get_unix_time_from_system())
		var last: int = Config.get_last_update_check()
		if now - last < CHECK_INTERVAL_SEC:
			return

	_check_in_progress = true
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(
		_on_check_completed.bind(manual, http)
	)
	var headers: PackedStringArray = PackedStringArray([
		"User-Agent: daccord/%s" % Client.app_version,
		"Accept: application/vnd.github+json",
	])
	var err := http.request(GITHUB_RELEASES_URL, headers)
	if err != OK:
		_check_in_progress = false
		http.queue_free()
		if manual:
			AppState.update_check_failed.emit(
				"HTTP request failed (error %d)" % err
			)


func _on_check_completed(
	result: int, response_code: int, _headers: PackedStringArray,
	body: PackedByteArray, manual: bool, http: HTTPRequest,
) -> void:
	http.queue_free()
	_check_in_progress = false

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		if manual:
			AppState.update_check_failed.emit(
				"GitHub API returned %d" % response_code
				if result == HTTPRequest.RESULT_SUCCESS
				else "Network error (result %d)" % result
			)
		return

	var json = JSON.parse_string(body.get_string_from_utf8())
	if json == null or not json is Dictionary:
		if manual:
			AppState.update_check_failed.emit("Invalid JSON response")
		return

	var info: Dictionary = _parse_release(json)
	if info.is_empty():
		if manual:
			AppState.update_check_failed.emit(
				"Could not parse release data"
			)
		return

	# Record successful check
	Config.set_last_update_check(
		int(Time.get_unix_time_from_system())
	)

	# Start periodic timer after first successful check
	if _periodic_timer.is_stopped():
		_periodic_timer.start()

	var remote_version: String = info.get("version", "")
	var current_version: String = Client.app_version
	var current_parsed: Dictionary = parse_semver(current_version)
	var current_is_pre: bool = not current_parsed.get("pre", "").is_empty()

	# Skip pre-release versions unless user is on a pre-release build
	if info.get("prerelease", false) and not current_is_pre:
		if manual:
			AppState.update_check_complete.emit(null)
		return

	if is_newer(remote_version, current_version):
		_latest_version_info = info
		# Respect skipped version (persistent)
		var skipped: String = Config.get_skipped_version()
		if not manual and remote_version == skipped:
			return
		# Respect dismissed version (session-only)
		if not manual and remote_version == _dismissed_version:
			return
		AppState.update_available.emit(info)
	else:
		if manual:
			AppState.update_check_complete.emit(info)


static func _parse_release(data: Dictionary) -> Dictionary:
	var tag: String = data.get("tag_name", "")
	if tag.is_empty():
		return {}

	var parsed: Dictionary = parse_semver(tag)
	if not parsed.get("valid", false):
		return {}

	var version: String = tag
	if version.begins_with("v"):
		version = version.substr(1)

	var release_url: String = data.get("html_url", "")
	var notes: String = data.get("body", "")
	var prerelease: bool = data.get("prerelease", false)

	# Find platform-appropriate asset
	var download_url := ""
	var download_size: int = 0
	var assets: Array = data.get("assets", [])
	var platform_key: String = OS.get_name().to_lower()
	var best_asset := {}
	var fallback_asset := {}

	for asset in assets:
		if not asset is Dictionary:
			continue
		var aname: String = asset.get("name", "").to_lower()
		if not aname.contains(platform_key):
			continue
		if platform_key == "linux":
			var arch: String = Engine.get_architecture_name()
			if aname.contains(arch):
				best_asset = asset
				break
			if fallback_asset.is_empty():
				fallback_asset = asset
		elif platform_key == "windows":
			if aname.contains("setup"):
				best_asset = asset
				break
			if fallback_asset.is_empty():
				fallback_asset = asset
		elif platform_key == "macos":
			if aname.ends_with(".dmg"):
				best_asset = asset
				break
			if fallback_asset.is_empty():
				fallback_asset = asset
		else:
			if fallback_asset.is_empty():
				fallback_asset = asset

	var chosen: Dictionary = best_asset if not best_asset.is_empty() \
			else fallback_asset
	if not chosen.is_empty():
		download_url = chosen.get("browser_download_url", "")
		download_size = chosen.get("size", 0)

	return {
		"version": version,
		"tag": tag,
		"release_url": release_url,
		"notes": notes,
		"prerelease": prerelease,
		"download_url": download_url,
		"download_size": download_size,
	}


func dismiss_version(version: String) -> void:
	_dismissed_version = version


func skip_version(version: String) -> void:
	Config.set_skipped_version(version)


func get_latest_version_info() -> Dictionary:
	return _latest_version_info


func is_downloading() -> bool:
	return _downloading


func is_update_ready() -> bool:
	return _update_ready


# ------------------------------------------------------------------
# Download, extract, install, restart
# ------------------------------------------------------------------

func _process(_delta: float) -> void:
	if not _downloading or _download_http == null:
		return
	var body_size: int = _download_http.get_body_size()
	if body_size <= 0:
		return
	var downloaded: int = _download_http.get_downloaded_bytes()
	var percent: float = (float(downloaded) / float(body_size)) * 100.0
	AppState.update_download_progress.emit(percent)


func download_update(version_info: Dictionary) -> void:
	if _downloading:
		return

	var download_url: String = version_info.get("download_url", "")
	var version: String = version_info.get("version", "")

	# Non-Linux platforms fall back to browser
	if OS.get_name() != "Linux" or download_url.is_empty():
		var url: String = version_info.get("release_url", "")
		if not url.is_empty():
			OS.shell_open(url)
		return

	_downloading = true
	_download_version = version
	_download_path = "user://daccord-update-%s.tar.gz" % version
	var global_path: String = ProjectSettings.globalize_path(_download_path)

	_download_http = HTTPRequest.new()
	_download_http.download_file = global_path
	_download_http.use_threads = true
	add_child(_download_http)
	_download_http.request_completed.connect(_on_download_completed)

	var headers: PackedStringArray = PackedStringArray([
		"User-Agent: daccord/%s" % Client.app_version,
		"Accept: application/octet-stream",
	])
	var err := _download_http.request(download_url, headers)
	if err != OK:
		_cleanup_download()
		AppState.update_download_failed.emit(
			"HTTP request failed (error %d)" % err
		)
		return

	AppState.update_download_started.emit()


func cancel_download() -> void:
	if not _downloading:
		return
	if _download_http and is_instance_valid(_download_http):
		_download_http.cancel_request()
	_cleanup_download()


func _cleanup_download() -> void:
	_downloading = false
	if _download_http and is_instance_valid(_download_http):
		_download_http.queue_free()
	_download_http = null
	# Remove partial download
	var global_path: String = ProjectSettings.globalize_path(_download_path)
	if not _download_path.is_empty() and FileAccess.file_exists(_download_path):
		DirAccess.remove_absolute(global_path)
	_download_path = ""


func _on_download_completed(
	result: int, response_code: int, _headers: PackedStringArray,
	_body: PackedByteArray,
) -> void:
	if not _downloading:
		return
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		var err_msg: String
		if result != HTTPRequest.RESULT_SUCCESS:
			err_msg = "Network error (result %d)" % result
		else:
			err_msg = "Server returned %d" % response_code
		_cleanup_download()
		AppState.update_download_failed.emit(err_msg)
		return

	_downloading = false
	if _download_http and is_instance_valid(_download_http):
		_download_http.queue_free()
	_download_http = null

	# Extract the update
	var extract_result: Dictionary = _extract_update(_download_path)
	if extract_result.has("error"):
		AppState.update_download_failed.emit(extract_result["error"])
		return

	_staged_binary_path = extract_result["binary_path"]
	_update_ready = true
	AppState.update_download_complete.emit(_staged_binary_path)


func _extract_update(archive_path: String) -> Dictionary:
	var global_archive: String = ProjectSettings.globalize_path(archive_path)
	var staging_dir: String = ProjectSettings.globalize_path(
		"user://update_staging"
	)

	# Create staging directory
	DirAccess.make_dir_recursive_absolute(staging_dir)

	# Extract tar.gz
	var output: Array = []
	var exit_code: int = OS.execute(
		"tar", ["xzf", global_archive, "-C", staging_dir], output
	)
	if exit_code != 0:
		return {"error": "Failed to extract update (exit code %d)" % exit_code}

	# Find the binary in staging
	var binary_path: String = _find_binary_in_dir(staging_dir)
	if binary_path.is_empty():
		return {"error": "Could not find binary in extracted update"}

	# Make it executable
	OS.execute("chmod", ["+x", binary_path])

	return {"binary_path": binary_path}


func _find_binary_in_dir(dir_path: String) -> String:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return ""
	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		var full_path: String = dir_path + "/" + fname
		if dir.current_is_dir():
			# Recurse into subdirectories
			var found := _find_binary_in_dir(full_path)
			if not found.is_empty():
				dir.list_dir_end()
				return found
		else:
			# Look for the daccord binary (not .tar.gz, not .so, not .txt)
			var lower: String = fname.to_lower()
			if lower.begins_with("daccord") and not lower.ends_with(".tar.gz") \
					and not lower.ends_with(".so") and not lower.ends_with(".txt") \
					and not lower.ends_with(".md") and not lower.ends_with(".pck"):
				dir.list_dir_end()
				return full_path
		fname = dir.get_next()
	dir.list_dir_end()
	return ""


func apply_update_and_restart() -> void:
	if not _update_ready or _staged_binary_path.is_empty():
		return

	# Save any draft messages
	_save_draft_messages()

	var current_binary: String = OS.get_executable_path()
	var old_binary: String = current_binary + ".old"

	# Rename current binary to .old
	var rename_err: int = DirAccess.rename_absolute(
		current_binary, old_binary
	)
	if rename_err != OK:
		push_error("[Updater] Failed to rename current binary: %d" % rename_err)
		AppState.update_download_failed.emit(
			"Failed to replace binary (error %d)" % rename_err
		)
		return

	# Copy new binary into place
	var copy_err: int = DirAccess.copy_absolute(
		_staged_binary_path, current_binary
	)
	if copy_err != OK:
		# Restore old binary
		DirAccess.rename_absolute(old_binary, current_binary)
		push_error("[Updater] Failed to copy new binary: %d" % copy_err)
		AppState.update_download_failed.emit(
			"Failed to copy new binary (error %d)" % copy_err
		)
		return

	# Make executable
	OS.execute("chmod", ["+x", current_binary])

	# Launch new binary and quit
	var args: PackedStringArray = OS.get_cmdline_args()
	OS.create_process(current_binary, args)
	get_tree().quit()


func _save_draft_messages() -> void:
	# Walk the scene tree to find any composer with text
	var composers := _find_nodes_by_class(get_tree().root, "TextEdit")
	for text_edit in composers:
		# Find the composer parent
		var parent: Node = text_edit.get_parent()
		while parent != null:
			if parent.has_method("set_channel_name"):
				# This is a composer
				var text: String = text_edit.text.strip_edges()
				if not text.is_empty() and not AppState.current_channel_id.is_empty():
					Config.set_draft_text(
						AppState.current_channel_id, text
					)
				break
			parent = parent.get_parent()


func _find_nodes_by_class(root: Node, class_name_str: String) -> Array:
	var result: Array = []
	if root.get_class() == class_name_str:
		result.append(root)
	for child in root.get_children():
		result.append_array(_find_nodes_by_class(child, class_name_str))
	return result


# ------------------------------------------------------------------
# Semver utilities (static)
# ------------------------------------------------------------------

static func parse_semver(version_string: String) -> Dictionary:
	var v := version_string.strip_edges()
	if v.begins_with("v"):
		v = v.substr(1)
	# Split off pre-release suffix (e.g. "1.2.0-beta.1" -> "1.2.0", "beta.1")
	var pre := ""
	var dash_pos: int = v.find("-")
	if dash_pos != -1:
		pre = v.substr(dash_pos + 1)
		v = v.substr(0, dash_pos)
	var parts: PackedStringArray = v.split(".")
	if parts.size() < 3:
		return {"valid": false, "major": 0, "minor": 0, "patch": 0, "pre": ""}
	if not parts[0].is_valid_int() or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return {"valid": false, "major": 0, "minor": 0, "patch": 0, "pre": ""}
	return {
		"valid": true,
		"major": parts[0].to_int(),
		"minor": parts[1].to_int(),
		"patch": parts[2].to_int(),
		"pre": pre,
	}


## Returns 1 if a > b, -1 if a < b, 0 if equal.
## Pre-release versions are considered older than the same version
## without a pre-release suffix (e.g. 1.2.0-beta < 1.2.0).
static func compare_semver(a: String, b: String) -> int:
	var pa: Dictionary = parse_semver(a)
	var pb: Dictionary = parse_semver(b)
	if not pa["valid"] or not pb["valid"]:
		return 0
	# Compare major.minor.patch
	if pa["major"] != pb["major"]:
		return 1 if pa["major"] > pb["major"] else -1
	if pa["minor"] != pb["minor"]:
		return 1 if pa["minor"] > pb["minor"] else -1
	if pa["patch"] != pb["patch"]:
		return 1 if pa["patch"] > pb["patch"] else -1
	# Same major.minor.patch -- compare pre-release
	var a_pre: String = pa["pre"]
	var b_pre: String = pb["pre"]
	if a_pre.is_empty() and b_pre.is_empty():
		return 0
	# No pre-release is higher than any pre-release
	if a_pre.is_empty():
		return 1
	if b_pre.is_empty():
		return -1
	# Both have pre-release: lexicographic compare
	if a_pre < b_pre:
		return -1
	if a_pre > b_pre:
		return 1
	return 0


## Convenience: returns true if remote_version is strictly newer than
## current_version.
static func is_newer(remote_version: String, current_version: String) -> bool:
	return compare_semver(remote_version, current_version) > 0
