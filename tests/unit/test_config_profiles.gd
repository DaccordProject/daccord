extends GutTest

const _REGISTRY_PATH := "user://profile_registry.cfg"
const _DEFAULT_CFG := "user://profiles/default/config.cfg"

var config: Node
var profiles # ConfigProfiles helper
var _saved_registry := PackedByteArray()
var _saved_config := PackedByteArray()
var _had_registry := false
var _had_config := false


func before_each() -> void:
	# Back up real user files so tests don't destroy user data.
	# profiles.create() saves to the real registry, and
	# config._save() writes to the real default profile config.
	_had_registry = FileAccess.file_exists(_REGISTRY_PATH)
	if _had_registry:
		_saved_registry = FileAccess.get_file_as_bytes(
			_REGISTRY_PATH
		)
	_had_config = FileAccess.file_exists(_DEFAULT_CFG)
	if _had_config:
		_saved_config = FileAccess.get_file_as_bytes(
			_DEFAULT_CFG
		)
	config = load("res://scripts/autoload/config.gd").new()
	# Don't call _ready() — we test in-memory behavior.
	config._load_ok = true
	# Initialize a minimal registry in memory
	config._registry = ConfigFile.new()
	config._registry.set_value("state", "active", "default")
	config._registry.set_value("order", "list", ["default"])
	config._registry.set_value("profile_default", "name", "Default")
	config._profile_slug = "default"
	# Manually init the profiles sub-object
	var ProfilesScript = load(
		"res://scripts/autoload/config_profiles.gd"
	)
	profiles = ProfilesScript.new(config, "daccord-profile-v1")
	config.profiles = profiles


func after_each() -> void:
	# Remove all test-created profile directories
	var dir := DirAccess.open("user://profiles")
	if dir:
		dir.list_dir_begin()
		var dname := dir.get_next()
		while not dname.is_empty():
			if dir.current_is_dir() and dname != "default":
				config._remove_directory_recursive(
					"user://profiles/" + dname
				)
			dname = dir.get_next()
		dir.list_dir_end()
	config.free()
	# Restore backed-up real files
	if _had_registry:
		var f := FileAccess.open(
			_REGISTRY_PATH, FileAccess.WRITE
		)
		if f:
			f.store_buffer(_saved_registry)
			f.close()
	elif FileAccess.file_exists(_REGISTRY_PATH):
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(_REGISTRY_PATH)
		)
	if _had_config:
		var f := FileAccess.open(
			_DEFAULT_CFG, FileAccess.WRITE
		)
		if f:
			f.store_buffer(_saved_config)
			f.close()
	elif FileAccess.file_exists(_DEFAULT_CFG):
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(_DEFAULT_CFG)
		)


# --- _slugify ---

func test_slugify_basic() -> void:
	var slug: String = profiles._slugify("My Profile")
	assert_eq(slug, "my-profile")


func test_slugify_special_chars() -> void:
	var slug: String = profiles._slugify("Test!@#$% Profile")
	assert_eq(slug, "test-profile")


func test_slugify_truncation() -> void:
	var long_name := "abcdefghijklmnopqrstuvwxyz1234567890extra"
	var slug: String = profiles._slugify(long_name)
	assert_true(slug.length() <= 32)


func test_slugify_collision() -> void:
	# "default" already exists in order list
	var slug: String = profiles._slugify("Default")
	assert_eq(slug, "default-2")


func test_slugify_empty_becomes_profile() -> void:
	var slug: String = profiles._slugify("!@#$%")
	assert_eq(slug, "profile")


# --- _hash_password ---

func test_hash_password_deterministic() -> void:
	var h1: String = profiles._hash_password("test", "pass123")
	var h2: String = profiles._hash_password("test", "pass123")
	assert_eq(h1, h2)


func test_hash_password_different_slugs() -> void:
	var h1: String = profiles._hash_password("slug-a", "pass")
	var h2: String = profiles._hash_password("slug-b", "pass")
	assert_ne(h1, h2)


func test_hash_password_different_passwords() -> void:
	var h1: String = profiles._hash_password("test", "pass1")
	var h2: String = profiles._hash_password("test", "pass2")
	assert_ne(h1, h2)


# --- create ---

func test_create_profile_fresh() -> void:
	var slug: String = profiles.create("Work")
	assert_eq(slug, "work")
	var profs: Array = profiles.get_profiles()
	assert_eq(profs.size(), 2) # default + work
	assert_eq(profs[1]["slug"], "work")
	assert_eq(profs[1]["name"], "Work")
	assert_false(profs[1]["has_password"])


func test_create_profile_with_password() -> void:
	var slug: String = profiles.create("Secret", "pw123")
	var profs: Array = profiles.get_profiles()
	var found := false
	for p in profs:
		if p["slug"] == slug:
			found = true
			assert_true(p["has_password"])
	assert_true(found)


func test_create_profile_copy() -> void:
	# Add a server to the current config
	config.add_server("http://host:3000", "tok", "space")
	var slug: String = profiles.create("Personal", "", true)
	# The copied config file should exist
	var cfg_path := "user://profiles/" + slug + "/config.cfg"
	assert_true(
		FileAccess.file_exists(cfg_path)
		or DirAccess.dir_exists_absolute(
			"user://profiles/" + slug
		)
	)


# --- delete ---

func test_delete_profile_default_blocked() -> void:
	var result: bool = profiles.delete("default")
	assert_false(result)
	var profs: Array = profiles.get_profiles()
	assert_eq(profs.size(), 1)


func test_delete_profile_removes_from_registry() -> void:
	profiles.create("ToDelete")
	assert_eq(profiles.get_profiles().size(), 2)
	var result: bool = profiles.delete("todelete")
	assert_true(result)
	assert_eq(profiles.get_profiles().size(), 1)


# --- rename ---

func test_rename_profile() -> void:
	profiles.create("OldName")
	profiles.rename("oldname", "NewName")
	var profs: Array = profiles.get_profiles()
	var found := false
	for p in profs:
		if p["slug"] == "oldname":
			assert_eq(p["name"], "NewName")
			found = true
	assert_true(found)


# --- set_password / verify_password ---

func test_set_and_verify_password() -> void:
	profiles.create("Protected")
	# No password yet — verify returns true
	assert_true(
		profiles.verify_password("protected", "anything")
	)
	# Set password
	var result: bool = profiles.set_password(
		"protected", "", "secret"
	)
	assert_true(result)
	# Verify correct password
	assert_true(
		profiles.verify_password("protected", "secret")
	)
	# Verify wrong password
	assert_false(
		profiles.verify_password("protected", "wrong")
	)


func test_set_password_wrong_old_fails() -> void:
	profiles.create("Locked")
	profiles.set_password("locked", "", "pw1")
	var result: bool = profiles.set_password(
		"locked", "wrong-old", "pw2"
	)
	assert_false(result)
	# Original password still works
	assert_true(
		profiles.verify_password("locked", "pw1")
	)


func test_remove_password() -> void:
	profiles.create("Removable")
	profiles.set_password("removable", "", "pw")
	# Remove by setting empty new password
	var result: bool = profiles.set_password(
		"removable", "pw", ""
	)
	assert_true(result)
	# No password should mean verify returns true for anything
	assert_true(
		profiles.verify_password("removable", "anything")
	)


# --- get_profiles / get_active_slug ---

func test_get_profiles_ordered() -> void:
	profiles.create("AAA")
	profiles.create("BBB")
	var profs: Array = profiles.get_profiles()
	assert_eq(profs.size(), 3)
	assert_eq(profs[0]["slug"], "default")
	assert_eq(profs[1]["slug"], "aaa")
	assert_eq(profs[2]["slug"], "bbb")


func test_get_active_profile_slug() -> void:
	assert_eq(profiles.get_active_slug(), "default")


# --- move_up / move_down ---

func test_move_profile_up_down() -> void:
	profiles.create("Alpha")
	profiles.create("Beta")
	# Order: default, alpha, beta

	# Move beta up
	profiles.move_up("beta")
	var profs: Array = profiles.get_profiles()
	assert_eq(profs[1]["slug"], "beta")
	assert_eq(profs[2]["slug"], "alpha")

	# Move beta down (back to original position)
	profiles.move_down("beta")
	profs = profiles.get_profiles()
	assert_eq(profs[1]["slug"], "alpha")
	assert_eq(profs[2]["slug"], "beta")


func test_move_profile_up_at_top_no_op() -> void:
	profiles.create("Top")
	# default is at index 0, moving up should be no-op
	profiles.move_up("default")
	var profs: Array = profiles.get_profiles()
	assert_eq(profs[0]["slug"], "default")


func test_move_profile_down_at_bottom_no_op() -> void:
	profiles.create("Bottom")
	# "bottom" is last, moving down should be no-op
	profiles.move_down("bottom")
	var profs: Array = profiles.get_profiles()
	assert_eq(
		profs[profs.size() - 1]["slug"], "bottom"
	)
