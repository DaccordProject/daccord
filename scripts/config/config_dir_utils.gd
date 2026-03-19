class_name ConfigDirUtils
extends RefCounted

## Static directory helper methods used by Config and ConfigProfiles.


static func copy_directory(src: String, dst: String) -> void:
	var dir := DirAccess.open(src)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		if not dir.current_is_dir():
			DirAccess.copy_absolute(
				ProjectSettings.globalize_path(src + "/" + fname),
				ProjectSettings.globalize_path(dst + "/" + fname)
			)
		fname = dir.get_next()
	dir.list_dir_end()


static func remove_directory_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		var full := path + "/" + fname
		if dir.current_is_dir():
			remove_directory_recursive(full)
		else:
			DirAccess.remove_absolute(
				ProjectSettings.globalize_path(full)
			)
		fname = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(path)
	)
