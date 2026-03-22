extends GutTest

## Unit tests for PluginDownloadManager — SHA-256 hashing, cache directory
## URI encoding, signature verification stub, and hash file cache checks.

var manager: PluginDownloadManager
var client: Node


func before_each() -> void:
	client = load("res://scripts/autoload/client.gd").new()
	manager = PluginDownloadManager.new(client)


func after_each() -> void:
	manager = null
	client.free()


# ------------------------------------------------------------------
# _sha256_hex
# ------------------------------------------------------------------

func test_sha256_hex_known_value() -> void:
	# SHA-256 of empty byte array
	var data := PackedByteArray()
	var hash_val: String = manager._sha256_hex(data)
	# Known SHA-256 of empty input:
	# e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
	assert_eq(
		hash_val,
		"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
	)


func test_sha256_hex_hello_world() -> void:
	var data: PackedByteArray = "hello world".to_utf8_buffer()
	var hash_val: String = manager._sha256_hex(data)
	# Known SHA-256 of "hello world"
	assert_eq(
		hash_val,
		"b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"
	)


func test_sha256_hex_deterministic() -> void:
	var data: PackedByteArray = "test data 12345".to_utf8_buffer()
	var h1: String = manager._sha256_hex(data)
	var h2: String = manager._sha256_hex(data)
	assert_eq(h1, h2)


func test_sha256_hex_different_inputs_differ() -> void:
	var h1: String = manager._sha256_hex("aaa".to_utf8_buffer())
	var h2: String = manager._sha256_hex("bbb".to_utf8_buffer())
	assert_ne(h1, h2)


# ------------------------------------------------------------------
# _cache_dir — URI encoding
# ------------------------------------------------------------------

func test_cache_dir_simple_ids() -> void:
	var dir_path: String = manager._cache_dir("server1", "plugin1")
	assert_eq(dir_path, "user://plugins/server1/plugin1")


func test_cache_dir_special_characters_encoded() -> void:
	var dir_path: String = manager._cache_dir("http://evil.com", "../../etc")
	# URI encoding encodes : and / characters, preventing direct path traversal
	assert_true(dir_path.contains("plugins/"))
	assert_true(dir_path.begins_with("user://plugins/"))


func test_cache_dir_spaces_encoded() -> void:
	var dir_path: String = manager._cache_dir("my server", "my plugin")
	assert_false(dir_path.contains(" "))


# ------------------------------------------------------------------
# _verify_signature — stub behavior
# ------------------------------------------------------------------

func test_verify_signature_returns_false_when_no_sig_file() -> void:
	# Non-existent directory — no plugin.sig exists
	var result: bool = manager._verify_signature(
		"user://nonexistent_test_dir_xyz", "server1"
	)
	assert_false(result)


func test_verify_signature_returns_true_when_sig_exists() -> void:
	# Create a temp dir with a plugin.sig file
	var dir_path := "user://test_sig_verify"
	DirAccess.make_dir_recursive_absolute(dir_path)
	var sig_path := dir_path.path_join("plugin.sig")
	var f := FileAccess.open(sig_path, FileAccess.WRITE)
	f.store_string("")  # Empty signature — still passes the stub!
	f.close()

	var result: bool = manager._verify_signature(dir_path, "server1")
	assert_true(result, "Stub accepts any plugin.sig — security gap")

	# Cleanup
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(sig_path)
	)
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(dir_path)
	)


# ------------------------------------------------------------------
# is_cached
# ------------------------------------------------------------------

func test_is_cached_empty_hash_returns_false() -> void:
	assert_false(manager.is_cached("server1", "plugin1", ""))


func test_is_cached_no_hash_file_returns_false() -> void:
	assert_false(
		manager.is_cached("server1", "plugin1", "abc123")
	)


func test_is_cached_matching_hash_returns_true() -> void:
	var dir_path: String = manager._cache_dir("test_server", "test_plugin")
	DirAccess.make_dir_recursive_absolute(dir_path)
	var hash_file := dir_path.path_join(".bundle_hash")
	var f := FileAccess.open(hash_file, FileAccess.WRITE)
	f.store_string("expected_hash_value")
	f.close()

	assert_true(
		manager.is_cached("test_server", "test_plugin", "expected_hash_value")
	)

	# Cleanup
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(hash_file)
	)
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(dir_path)
	)


func test_is_cached_mismatched_hash_returns_false() -> void:
	var dir_path: String = manager._cache_dir("test_server2", "test_plugin2")
	DirAccess.make_dir_recursive_absolute(dir_path)
	var hash_file := dir_path.path_join(".bundle_hash")
	var f := FileAccess.open(hash_file, FileAccess.WRITE)
	f.store_string("stored_hash")
	f.close()

	assert_false(
		manager.is_cached("test_server2", "test_plugin2", "different_hash")
	)

	# Cleanup
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(hash_file)
	)
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(dir_path)
	)


# ------------------------------------------------------------------
# _write_hash_file
# ------------------------------------------------------------------

func test_write_hash_file_creates_file() -> void:
	var dir_path := "user://test_write_hash"
	DirAccess.make_dir_recursive_absolute(dir_path)

	manager._write_hash_file(dir_path, "my_hash_123")

	var hash_file := dir_path.path_join(".bundle_hash")
	assert_true(FileAccess.file_exists(hash_file))
	var content: String = FileAccess.get_file_as_string(hash_file)
	assert_eq(content, "my_hash_123")

	# Cleanup
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(hash_file)
	)
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(dir_path)
	)


# ------------------------------------------------------------------
# MAX_BUNDLE_SIZE constant
# ------------------------------------------------------------------

func test_max_bundle_size_is_50mb() -> void:
	assert_eq(PluginDownloadManager.MAX_BUNDLE_SIZE, 50 * 1024 * 1024)


# ------------------------------------------------------------------
# _server_id_for_conn
# ------------------------------------------------------------------

func test_server_id_for_conn_uses_space_id() -> void:
	var conn := {"space_id": "space_abc"}
	var sid: String = manager._server_id_for_conn(conn)
	assert_eq(sid, "space_abc")


func test_server_id_for_conn_empty_space_id_falls_back() -> void:
	var conn := {"space_id": ""}
	# With no client, should return "unknown"
	var sid: String = manager._server_id_for_conn(conn)
	assert_eq(sid, "unknown")


# ------------------------------------------------------------------
# _extract_zip — valid ZIP extraction
# ------------------------------------------------------------------

func test_extract_zip_creates_files() -> void:
	var zip_bytes: PackedByteArray = _build_zip({
		"plugin.json": '{"name": "test"}'.to_utf8_buffer(),
		"src/main.lua": "print('hi')".to_utf8_buffer(),
	})
	var dest := "user://test_extract_zip_basic"
	var ok: bool = manager._extract_zip(zip_bytes, dest)

	assert_true(ok)
	assert_true(FileAccess.file_exists(dest.path_join("plugin.json")))
	assert_true(FileAccess.file_exists(dest.path_join("src/main.lua")))
	var content: String = FileAccess.get_file_as_string(
		dest.path_join("plugin.json")
	)
	assert_eq(content, '{"name": "test"}')

	# Cleanup
	manager._remove_dir_recursive(dest)


func test_extract_zip_handles_subdirectories() -> void:
	var zip_bytes: PackedByteArray = _build_zip({
		"a/b/c/deep.txt": "deep content".to_utf8_buffer(),
	})
	var dest := "user://test_extract_zip_subdirs"
	var ok: bool = manager._extract_zip(zip_bytes, dest)

	assert_true(ok)
	assert_true(FileAccess.file_exists(dest.path_join("a/b/c/deep.txt")))
	var content: String = FileAccess.get_file_as_string(
		dest.path_join("a/b/c/deep.txt")
	)
	assert_eq(content, "deep content")

	manager._remove_dir_recursive(dest)


func test_extract_zip_invalid_data_returns_false() -> void:
	var bad_bytes: PackedByteArray = "not a zip file".to_utf8_buffer()
	var dest := "user://test_extract_zip_invalid"
	var ok: bool = manager._extract_zip(bad_bytes, dest)

	assert_false(ok)
	assert_push_error(1)  # push_error from ZIP open failure


func test_extract_zip_cleans_up_temp_file() -> void:
	var zip_bytes: PackedByteArray = _build_zip({
		"test.txt": "hello".to_utf8_buffer(),
	})
	var dest := "user://test_extract_zip_temp"
	var tmp_path := dest + ".tmp.zip"

	manager._extract_zip(zip_bytes, dest)

	# Temp file should be cleaned up after extraction
	assert_false(FileAccess.file_exists(tmp_path))

	manager._remove_dir_recursive(dest)


func test_extract_zip_overwrites_old_cache() -> void:
	var dest := "user://test_extract_zip_overwrite"
	# Create an old file that should be removed
	DirAccess.make_dir_recursive_absolute(dest)
	var old_file := dest.path_join("old_file.txt")
	var f := FileAccess.open(old_file, FileAccess.WRITE)
	f.store_string("old content")
	f.close()

	# Extract a new ZIP with different contents
	var zip_bytes: PackedByteArray = _build_zip({
		"new_file.txt": "new content".to_utf8_buffer(),
	})
	manager._extract_zip(zip_bytes, dest)

	# Old file should be gone, new file should exist
	assert_false(FileAccess.file_exists(old_file))
	assert_true(FileAccess.file_exists(dest.path_join("new_file.txt")))

	manager._remove_dir_recursive(dest)


# ------------------------------------------------------------------
# ZIP path traversal — SECURITY TEST
# ------------------------------------------------------------------

func test_extract_zip_path_traversal_not_sanitized() -> void:
	# This test documents the known vulnerability: _extract_zip does NOT
	# sanitize "../" in ZIP entry paths. The code uses dest_dir.path_join(file_path)
	# without stripping ".." components. A malicious ZIP crafted outside Godot's
	# ZIPPacker (which rejects ../ entries) would write outside the cache dir.
	#
	# We verify the vulnerable code path exists by checking that path_join
	# does NOT strip ".." (the root cause of the vulnerability).
	var dest := "user://plugins/test_server/test_plugin"
	var traversal_path := "../../../etc/passwd"
	var resolved: String = dest.path_join(traversal_path)
	# path_join preserves ".." — this means _extract_zip would write outside dest
	assert_true(
		resolved.contains(".."),
		"path_join does not strip .. — ZIP traversal vulnerability exists"
	)


# ------------------------------------------------------------------
# _remove_dir_recursive
# ------------------------------------------------------------------

func test_remove_dir_recursive_cleans_nested_dirs() -> void:
	var base := "user://test_remove_recursive"
	DirAccess.make_dir_recursive_absolute(base.path_join("a/b"))
	# Create files at various levels
	var f1 := FileAccess.open(base.path_join("top.txt"), FileAccess.WRITE)
	f1.store_string("top")
	f1.close()
	var f2 := FileAccess.open(
		base.path_join("a/b/deep.txt"), FileAccess.WRITE
	)
	f2.store_string("deep")
	f2.close()

	manager._remove_dir_recursive(base)

	assert_false(DirAccess.dir_exists_absolute(base))


func test_remove_dir_recursive_noop_for_nonexistent() -> void:
	# Should not crash on non-existent path
	manager._remove_dir_recursive("user://nonexistent_remove_test_xyz")


# ------------------------------------------------------------------
# clear_cache
# ------------------------------------------------------------------

func test_clear_cache_removes_cached_dir() -> void:
	var server_id := "test_clear_srv"
	var plugin_id := "test_clear_plg"
	var dir_path: String = manager._cache_dir(server_id, plugin_id)
	DirAccess.make_dir_recursive_absolute(dir_path)
	var f := FileAccess.open(
		dir_path.path_join("test.txt"), FileAccess.WRITE
	)
	f.store_string("cached")
	f.close()

	manager.clear_cache(server_id, plugin_id)

	assert_false(DirAccess.dir_exists_absolute(dir_path))


func test_clear_cache_noop_for_uncached() -> void:
	# Should not crash
	manager.clear_cache("nonexistent_srv", "nonexistent_plg")


# ------------------------------------------------------------------
# get_cache_dir — public accessor
# ------------------------------------------------------------------

func test_get_cache_dir_delegates_to_cache_dir() -> void:
	var result: String = manager.get_cache_dir("srv1", "plg1")
	assert_eq(result, manager._cache_dir("srv1", "plg1"))


# ------------------------------------------------------------------
# Helper: build a ZIP from a Dictionary of path -> PackedByteArray
# ------------------------------------------------------------------

func _build_zip(files: Dictionary) -> PackedByteArray:
	var tmp_path := "user://test_helper_build.zip"
	var packer := ZIPPacker.new()
	packer.open(tmp_path)
	for path in files:
		packer.start_file(path)
		packer.write_file(files[path])
		packer.close_file()
	packer.close()
	var f := FileAccess.open(tmp_path, FileAccess.READ)
	var bytes: PackedByteArray = f.get_buffer(f.get_length())
	f.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_path))
	return bytes
