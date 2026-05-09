class_name UpdaterExtractor
extends RefCounted

## Stateless helpers for extracting downloaded update archives and locating
## the binary payload inside the staging directory.

const _STAGING_PATH := "user://update_staging"


## Extract a downloaded archive into the staging dir.
## Returns {"binary_path": String} on success, {"error": String} on failure.
static func extract_update(archive_path: String) -> Dictionary:
	var global_archive: String = ProjectSettings.globalize_path(archive_path)
	var staging_dir: String = ProjectSettings.globalize_path(_STAGING_PATH)

	DirAccess.make_dir_recursive_absolute(staging_dir)

	var extract_err: String = _run_extraction(global_archive, staging_dir)
	if not extract_err.is_empty():
		return {"error": extract_err}

	var payload_path: String = find_update_payload(staging_dir)
	if payload_path.is_empty():
		return {"error": "Could not find binary in extracted update"}

	if OS.get_name() == "Linux":
		OS.execute("chmod", ["+x", payload_path])

	return {"binary_path": payload_path}


static func _run_extraction(archive: String, staging_dir: String) -> String:
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


static func _extract_dmg(dmg_path: String, staging_dir: String) -> String:
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


static func _extract_zip(zip_path: String, dest_dir: String) -> int:
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


## Locate the platform-specific update payload inside an extracted directory.
static func find_update_payload(dir_path: String) -> String:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return ""
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
			var found := find_update_payload(full_path)
			if not found.is_empty():
				dir.list_dir_end()
				return found
		elif not match_dir and fname == expected_name:
			dir.list_dir_end()
			return full_path
		fname = dir.get_next()
	dir.list_dir_end()
	return ""
