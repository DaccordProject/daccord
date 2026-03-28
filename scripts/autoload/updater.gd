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
		# Wait for first space data before checking
		AppState.spaces_updated.connect(
			_on_first_spaces_updated, CONNECT_ONE_SHOT
		)
	else:
		# No servers configured -- check after a short delay
		var delay := get_tree().create_timer(STARTUP_DELAY_SEC)
		delay.timeout.connect(func(): check_for_updates(false))


func _on_first_spaces_updated() -> void:
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
			if aname.ends_with(".zip"):
				best_asset = asset
				break
			if fallback_asset.is_empty():
				fallback_asset = asset
		elif platform_key == "macos":
			var arch: String = Engine.get_architecture_name()
			if aname.ends_with(".dmg") and aname.contains(arch):
				best_asset = asset
				break
			if aname.ends_with(".dmg") and fallback_asset.is_empty():
				fallback_asset = asset
			elif aname.ends_with(".zip") and fallback_asset.is_empty():
				fallback_asset = asset
		elif platform_key == "android":
			if aname.ends_with(".apk"):
				var arch: String = Engine.get_architecture_name()
				if aname.contains(arch):
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

	# No downloadable asset: open release page in browser
	if download_url.is_empty():
		var url: String = version_info.get("release_url", "")
		if not url.is_empty():
			OS.shell_open(url)
		return

	_downloading = true
	_download_version = version
	var ext: String
	if OS.get_name() == "Android":
		ext = ".apk"
	elif OS.get_name() == "Linux":
		ext = ".tar.gz"
	elif download_url.ends_with(".dmg"):
		ext = ".dmg"
	else:
		ext = ".zip"
	_download_path = "user://daccord-update-%s%s" % [version, ext]
	var global_path: String = ProjectSettings.globalize_path(_download_path)

	_download_http = HTTPRequest.new()
	_download_http.download_file = global_path
	# Threaded downloads can fail to signal completion on Android
	_download_http.use_threads = OS.get_name() != "Android"
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

	# Android: APK is ready to install directly, no extraction needed
	if OS.get_name() == "Android":
		var apk_path: String = ProjectSettings.globalize_path(
			_download_path
		)
		_staged_binary_path = apk_path
		_update_ready = true
		AppState.update_download_complete.emit(apk_path)
		return

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

	# Extract archive
	var extract_err: String = _run_extraction(global_archive, staging_dir)
	if not extract_err.is_empty():
		return {"error": extract_err}

	# Find the update payload (binary on Linux/Windows, .app on macOS)
	var payload_path: String = _find_update_payload(staging_dir)
	if payload_path.is_empty():
		return {"error": "Could not find binary in extracted update"}

	if OS.get_name() == "Linux":
		OS.execute("chmod", ["+x", payload_path])

	return {"binary_path": payload_path}


func _run_extraction(archive: String, staging_dir: String) -> String:
	var output: Array = []
	if OS.get_name() == "Linux":
		var exit_code: int = OS.execute(
			"tar", ["xzf", archive, "-C", staging_dir], output
		)
		if exit_code != 0:
			return "Failed to extract update (exit code %d)" % exit_code
	elif OS.get_name() == "macOS":
		if archive.ends_with(".dmg"):
			return _extract_dmg(archive, staging_dir)
		var exit_code: int = OS.execute(
			"unzip", ["-o", archive, "-d", staging_dir], output
		)
		if exit_code != 0:
			return "Failed to extract update (exit %d)" % exit_code
	else:
		var zip_err := _extract_zip(archive, staging_dir)
		if zip_err != OK:
			return "Failed to extract update (error %d)" % zip_err
	return ""


func _extract_dmg(dmg_path: String, staging_dir: String) -> String:
	var output: Array = []
	var mount_point: String = staging_dir + "/_dmg_mount"
	DirAccess.make_dir_recursive_absolute(mount_point)
	var m_exit: int = OS.execute(
		"hdiutil", ["attach", dmg_path, "-nobrowse",
		"-mountpoint", mount_point], output
	)
	if m_exit != 0:
		return "Failed to mount DMG (exit %d)" % m_exit
	var cp_exit: int = OS.execute(
		"cp", ["-R", mount_point + "/daccord.app",
		staging_dir + "/daccord.app"], output
	)
	OS.execute("hdiutil", ["detach", mount_point, "-quiet"], output)
	if cp_exit != 0:
		return "Failed to copy app from DMG (exit %d)" % cp_exit
	return ""


func _extract_zip(zip_path: String, dest_dir: String) -> int:
	var reader := ZIPReader.new()
	var err := reader.open(zip_path)
	if err != OK:
		return err
	for file_path in reader.get_files():
		if file_path.ends_with("/"):
			DirAccess.make_dir_recursive_absolute(dest_dir + "/" + file_path)
			continue
		var dir_part: String = file_path.get_base_dir()
		if not dir_part.is_empty():
			DirAccess.make_dir_recursive_absolute(dest_dir + "/" + dir_part)
		var data: PackedByteArray = reader.read_file(file_path)
		var f := FileAccess.open(
			dest_dir + "/" + file_path, FileAccess.WRITE
		)
		if f == null:
			reader.close()
			return FileAccess.get_open_error()
		f.store_buffer(data)
		f.close()
	reader.close()
	return OK


func _find_update_payload(dir_path: String) -> String:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return ""
	# Match the expected name per platform
	var expected_name: String
	var match_dir: bool = false
	if OS.get_name() == "Windows":
		expected_name = "daccord.exe"
	elif OS.get_name() == "macOS":
		expected_name = "daccord.app"
		match_dir = true
	else:
		var arch: String = Engine.get_architecture_name()
		expected_name = "daccord.%s" % arch
	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		var full_path: String = dir_path + "/" + fname
		if dir.current_is_dir():
			if match_dir and fname == expected_name:
				dir.list_dir_end()
				return full_path
			var found := _find_update_payload(full_path)
			if not found.is_empty():
				dir.list_dir_end()
				return found
		elif not match_dir and fname == expected_name:
			dir.list_dir_end()
			return full_path
		fname = dir.get_next()
	dir.list_dir_end()
	return ""


func apply_update_and_restart() -> void:
	if not _update_ready or _staged_binary_path.is_empty():
		return

	_save_draft_messages()

	if OS.get_name() == "Android":
		_apply_android_update()
	elif OS.get_name() == "macOS":
		_apply_macos_update()
	else:
		_apply_binary_update()


func _apply_binary_update() -> void:
	var current_binary: String = OS.get_executable_path()
	var install_dir: String = current_binary.get_base_dir()
	var staged_dir: String = _staged_binary_path.get_base_dir()

	# Collect all files from staging (binary, .pck, shared libs, etc.)
	var staged_files: PackedStringArray = _list_dir_files(staged_dir)
	if staged_files.is_empty():
		AppState.update_download_failed.emit(
			"No files found in staging directory"
		)
		return

	# Windows: the running exe and pck are locked by the OS, so we
	# delegate replacement to a batch script that runs after we exit.
	if OS.get_name() == "Windows":
		_apply_windows_update(
			current_binary, install_dir, staged_dir, staged_files
		)
		return

	# Phase 1: Rename existing files to .old for rollback
	var renamed: Array[String] = []
	for fname in staged_files:
		var target: String = install_dir.path_join(fname)
		if FileAccess.file_exists(target):
			var old_path: String = target + ".old"
			if FileAccess.file_exists(old_path):
				DirAccess.remove_absolute(old_path)
			var err: int = DirAccess.rename_absolute(target, old_path)
			if err != OK:
				push_error(
					"[Updater] Failed to rename %s: %d" % [fname, err]
				)
				_rollback_old_files(install_dir, renamed)
				AppState.update_download_failed.emit(
					"Failed to replace %s (error %d)" % [fname, err]
				)
				return
			renamed.append(fname)

	# Phase 2: Copy all new files from staging to install directory
	for fname in staged_files:
		var src: String = staged_dir.path_join(fname)
		var dst: String = install_dir.path_join(fname)
		var err: int = DirAccess.copy_absolute(src, dst)
		if err != OK:
			push_error("[Updater] Failed to copy %s: %d" % [fname, err])
			_rollback_old_files(install_dir, renamed)
			AppState.update_download_failed.emit(
				"Failed to copy %s (error %d)" % [fname, err]
			)
			return

	# Phase 3: Restore executable permissions on Linux
	if OS.get_name() == "Linux":
		for fname in staged_files:
			var staged_path: String = staged_dir.path_join(fname)
			var target: String = install_dir.path_join(fname)
			# tar preserves permissions; replicate to the copied files
			if OS.execute("test", ["-x", staged_path]) == 0:
				OS.execute("chmod", ["+x", target])

	var args: PackedStringArray = OS.get_cmdline_args()
	OS.create_process(current_binary, args)
	get_tree().quit()


func _apply_windows_update(
	current_binary: String, install_dir: String,
	staged_dir: String, staged_files: PackedStringArray,
) -> void:
	# Build a batch script that waits for our process to exit, copies
	# the new files over the locked ones, then relaunches the app.
	var pid: int = OS.get_process_id()
	var bat_path: String = install_dir.path_join("_daccord_update.bat")

	var lines: PackedStringArray = PackedStringArray()
	lines.append("@echo off")
	# Wait for the running instance to exit (poll every second, up to 30s)
	lines.append(
		"for /L %%i in (1,1,30) do ("
	)
	lines.append(
		"  tasklist /FI \"PID eq %d\" 2>NUL | find /I \"%d\" >NUL || goto :do_copy"
		% [pid, pid]
	)
	lines.append("  timeout /t 1 /nobreak >NUL")
	lines.append(")")
	lines.append(":do_copy")
	for fname in staged_files:
		var src: String = staged_dir.path_join(fname)
		var dst: String = install_dir.path_join(fname)
		lines.append(
			"copy /y \"%s\" \"%s\" >NUL 2>&1" % [src, dst]
		)
	# Relaunch the updated binary
	var args_str: String = " ".join(OS.get_cmdline_args())
	lines.append(
		"start \"\" \"%s\" %s" % [current_binary, args_str]
	)
	# Clean up the batch script itself
	lines.append("del \"%~f0\"")

	var f := FileAccess.open(bat_path, FileAccess.WRITE)
	if f == null:
		AppState.update_download_failed.emit(
			"Failed to write update script (error %d)"
			% FileAccess.get_open_error()
		)
		return
	f.store_string("\r\n".join(lines) + "\r\n")
	f.close()

	# Launch the script hidden (no visible cmd window)
	OS.create_process("cmd.exe", PackedStringArray(["/c", bat_path]))
	get_tree().quit()


func _apply_android_update() -> void:
	# Launch the system package installer for the downloaded APK
	OS.shell_open(_staged_binary_path)


func _list_dir_files(dir_path: String) -> PackedStringArray:
	var files: PackedStringArray = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return files
	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		if not dir.current_is_dir():
			files.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()
	return files


func _rollback_old_files(dir: String, file_names: Array[String]) -> void:
	for fname in file_names:
		var target: String = dir.path_join(fname)
		var old_path: String = target + ".old"
		if FileAccess.file_exists(old_path):
			DirAccess.rename_absolute(old_path, target)


func _apply_macos_update() -> void:
	# Derive .app bundle path from executable path
	# e.g. /Applications/daccord.app/Contents/MacOS/daccord
	var current_exe: String = OS.get_executable_path()
	var app_bundle: String = current_exe.get_base_dir() \
			.get_base_dir().get_base_dir()
	var old_bundle: String = app_bundle + ".old"

	# Remove previous .old bundle if it exists
	if DirAccess.dir_exists_absolute(old_bundle):
		OS.execute("rm", ["-rf", old_bundle])

	# Rename current bundle to .old (macOS allows this while running)
	var rename_err: int = DirAccess.rename_absolute(
		app_bundle, old_bundle
	)
	if rename_err != OK:
		push_error("[Updater] Failed to rename app bundle: %d" % rename_err)
		AppState.update_download_failed.emit(
			"Failed to replace app bundle (error %d)" % rename_err
		)
		return

	# Copy new bundle preserving symlinks and permissions
	var output: Array = []
	var exit_code: int = OS.execute(
		"cp", ["-R", _staged_binary_path, app_bundle], output
	)
	if exit_code != 0:
		# Restore old bundle
		DirAccess.rename_absolute(old_bundle, app_bundle)
		push_error("[Updater] Failed to copy new app bundle")
		AppState.update_download_failed.emit(
			"Failed to copy new app bundle"
		)
		return

	# Remove quarantine attribute so Gatekeeper doesn't block the update
	OS.execute("xattr", ["-cr", app_bundle])

	# Relaunch from the new bundle
	var new_exe: String = app_bundle + "/Contents/MacOS/daccord"
	OS.create_process(new_exe, OS.get_cmdline_args())
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
