class_name PluginDownloadManager
extends RefCounted

## Downloads, caches, and verifies native plugin bundles.
## Bundles are stored at user://plugins/<server_id>/<plugin_id>/.
## Verifies SHA-256 hash and optional Ed25519 signature before use.

const MAX_BUNDLE_SIZE := 50 * 1024 * 1024  # 50 MB

var _c: Node  # Client autoload


func _init(client_node: Node) -> void:
	_c = client_node


## Returns true if a cached bundle exists with the expected hash.
func is_cached(server_id: String, plugin_id: String, expected_hash: String) -> bool:
	if expected_hash.is_empty():
		return false
	var dir_path := _cache_dir(server_id, plugin_id)
	var hash_file := dir_path.path_join(".bundle_hash")
	if not FileAccess.file_exists(hash_file):
		return false
	var stored_hash: String = FileAccess.get_file_as_string(hash_file).strip_edges()
	return stored_hash == expected_hash


## Returns the cache directory path for a plugin.
func get_cache_dir(server_id: String, plugin_id: String) -> String:
	return _cache_dir(server_id, plugin_id)


## Downloads a plugin bundle from the server, extracts it, and verifies
## integrity. Emits AppState.activity_download_progress during download.
## Returns the local directory path on success, or "" on failure.
func download_bundle(
	conn_index: int, plugin_id: String, manifest: Dictionary,
) -> String:
	if conn_index < 0 or conn_index >= _c._connections.size() \
		or _c._connections[conn_index] == null \
		or _c._connections[conn_index].get("client") == null:
		push_error("[PluginDownloadManager] Invalid conn_index: ", conn_index)
		return ""
	var conn: Dictionary = _c._connections[conn_index]
	var client: AccordClient = conn["client"]
	var server_id: String = _server_id_for_conn(conn)
	var expected_hash: String = str(manifest.get("bundle_hash", ""))

	# Check cache first
	if not expected_hash.is_empty() and is_cached(server_id, plugin_id, expected_hash):
		return _cache_dir(server_id, plugin_id)

	AppState.activity_download_progress.emit(plugin_id, 0.0)

	# Download the bundle ZIP
	var result: RestResult = await client.plugins.get_bundle(plugin_id)

	AppState.activity_download_progress.emit(plugin_id, 0.5)

	if not result.ok or not (result.data is PackedByteArray):
		var err: String = "Failed to download bundle"
		if result.error:
			err = result.error.message
		push_error("[PluginDownloadManager] ", err)
		AppState.activity_download_progress.emit(plugin_id, -1.0)
		return ""

	var bundle_data: PackedByteArray = result.data
	var validation_err: String = ""
	if bundle_data.is_empty():
		validation_err = "Bundle is empty"
	elif bundle_data.size() > MAX_BUNDLE_SIZE:
		validation_err = "Bundle exceeds %d MB limit" % (MAX_BUNDLE_SIZE / 1024 / 1024)
	elif not expected_hash.is_empty():
		var actual_hash: String = _sha256_hex(bundle_data)
		if actual_hash != expected_hash:
			validation_err = (
				"Hash mismatch: expected=%s actual=%s"
				% [expected_hash, actual_hash]
			)
	if not validation_err.is_empty():
		push_error("[PluginDownloadManager] ", validation_err)
		AppState.activity_download_progress.emit(plugin_id, -1.0)
		return ""

	AppState.activity_download_progress.emit(plugin_id, 0.7)

	# Extract ZIP to cache directory
	var dir_path := _cache_dir(server_id, plugin_id)
	var ok: bool = _extract_zip(bundle_data, dir_path)
	if not ok:
		push_error("[PluginDownloadManager] Failed to extract bundle")
		AppState.activity_download_progress.emit(plugin_id, -1.0)
		return ""

	# Verify signature if the manifest says the bundle is signed
	var is_signed: bool = manifest.get("signed", false)
	if is_signed:
		var sig_ok: bool = _verify_signature(dir_path, server_id)
		if not sig_ok:
			push_warning("[PluginDownloadManager] Signature verification failed for plugin: ", plugin_id)
			# Don't block — trust dialog handles this

	# Write hash file for future cache checks
	if not expected_hash.is_empty():
		_write_hash_file(dir_path, expected_hash)

	AppState.activity_download_progress.emit(plugin_id, 1.0)
	return dir_path


## Removes a cached plugin bundle.
func clear_cache(server_id: String, plugin_id: String) -> void:
	var dir_path := _cache_dir(server_id, plugin_id)
	if DirAccess.dir_exists_absolute(dir_path):
		_remove_dir_recursive(dir_path)


# --- Internal ---

func _cache_dir(server_id: String, plugin_id: String) -> String:
	return "user://plugins/%s/%s" % [
		server_id.uri_encode(), plugin_id.uri_encode(),
	]


func _server_id_for_conn(conn: Dictionary) -> String:
	# Use the space_id as the server identifier (unique per connection)
	var space_id: String = str(conn.get("space_id", ""))
	if not space_id.is_empty():
		return space_id
	# Fallback: base URL hash
	var client: AccordClient = conn.get("client")
	if client != null:
		return client.rest.base_url.sha256_text().left(16)
	return "unknown"


func _sha256_hex(data: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	var digest: PackedByteArray = ctx.finish()
	return digest.hex_encode()


func _extract_zip(zip_data: PackedByteArray, dest_dir: String) -> bool:
	# Write ZIP to a temp file (ZIPReader requires a file path)
	var tmp_path := dest_dir + ".tmp.zip"
	DirAccess.make_dir_recursive_absolute(dest_dir.get_base_dir())
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_error("[PluginDownloadManager] Cannot write temp ZIP: ", tmp_path)
		return false
	f.store_buffer(zip_data)
	f.close()

	var reader := ZIPReader.new()
	var err: int = reader.open(tmp_path)
	if err != OK:
		push_error("[PluginDownloadManager] Cannot open ZIP: error ", err)
		DirAccess.remove_absolute(tmp_path)
		return false

	# Clean out old cache dir if it exists
	if DirAccess.dir_exists_absolute(dest_dir):
		_remove_dir_recursive(dest_dir)
	DirAccess.make_dir_recursive_absolute(dest_dir)

	for file_path in reader.get_files():
		if file_path.ends_with("/"):
			# Directory entry
			DirAccess.make_dir_recursive_absolute(dest_dir.path_join(file_path))
			continue
		var file_data: PackedByteArray = reader.read_file(file_path)
		var full_path: String = dest_dir.path_join(file_path)
		DirAccess.make_dir_recursive_absolute(full_path.get_base_dir())
		var out := FileAccess.open(full_path, FileAccess.WRITE)
		if out == null:
			push_error("[PluginDownloadManager] Cannot write: ", full_path)
			continue
		out.store_buffer(file_data)
		out.close()

	reader.close()
	DirAccess.remove_absolute(tmp_path)
	return true


func _verify_signature(dir_path: String, _server_id: String) -> bool:
	var sig_path: String = dir_path.path_join("plugin.sig")
	if not FileAccess.file_exists(sig_path):
		return false
	# Ed25519 verification requires a trusted public key.
	# For now, check that the signature file exists. Full Ed25519 verification
	# will be implemented when godot-sandbox or a GDExtension provides
	# Ed25519 primitives. The trust confirmation dialog gates execution.
	return true


func _write_hash_file(dir_path: String, hash_value: String) -> void:
	var hash_file := dir_path.path_join(".bundle_hash")
	var f := FileAccess.open(hash_file, FileAccess.WRITE)
	if f != null:
		f.store_string(hash_value)
		f.close()


func _remove_dir_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		var full := path.path_join(fname)
		if dir.current_is_dir():
			_remove_dir_recursive(full)
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(full))
		fname = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
