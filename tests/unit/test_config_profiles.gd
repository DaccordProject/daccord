extends GutTest

var config: Node


func before_each() -> void:
	config = load("res://scripts/autoload/config.gd").new()
	# Don't call _ready() — we test in-memory behavior.
	config._load_ok = true
	# Initialize a minimal registry in memory
	config._registry = ConfigFile.new()
	config._registry.set_value("state", "active", "default")
	config._registry.set_value("order", "list", ["default"])
	config._registry.set_value("profile_default", "name", "Default")
	config._profile_slug = "default"


func after_each() -> void:
	# Clean up any test directories
	var test_dir := "user://profiles/test-profile"
	if DirAccess.dir_exists_absolute(test_dir):
		config._remove_directory_recursive(test_dir)
	var test_dir2 := "user://profiles/work"
	if DirAccess.dir_exists_absolute(test_dir2):
		config._remove_directory_recursive(test_dir2)
	var test_dir3 := "user://profiles/personal"
	if DirAccess.dir_exists_absolute(test_dir3):
		config._remove_directory_recursive(test_dir3)
	var test_dir4 := "user://profiles/my-profile"
	if DirAccess.dir_exists_absolute(test_dir4):
		config._remove_directory_recursive(test_dir4)
	var test_dir5 := "user://profiles/my-profile-2"
	if DirAccess.dir_exists_absolute(test_dir5):
		config._remove_directory_recursive(test_dir5)
	var test_dir6 := "user://profiles/profile"
	if DirAccess.dir_exists_absolute(test_dir6):
		config._remove_directory_recursive(test_dir6)
	var test_dir7 := "user://profiles/abcdefghijklmnopqrstuvwxyz123456"
	if DirAccess.dir_exists_absolute(test_dir7):
		config._remove_directory_recursive(test_dir7)
	config.free()


# --- _slugify ---

func test_slugify_basic() -> void:
	var slug: String = config._slugify("My Profile")
	assert_eq(slug, "my-profile")


func test_slugify_special_chars() -> void:
	var slug: String = config._slugify("Test!@#$% Profile")
	assert_eq(slug, "test-profile")


func test_slugify_truncation() -> void:
	var long_name := "abcdefghijklmnopqrstuvwxyz1234567890extra"
	var slug: String = config._slugify(long_name)
	assert_true(slug.length() <= 32)


func test_slugify_collision() -> void:
	# "default" already exists in order list
	var slug: String = config._slugify("Default")
	assert_eq(slug, "default-2")


func test_slugify_empty_becomes_profile() -> void:
	var slug: String = config._slugify("!@#$%")
	assert_eq(slug, "profile")


# --- _hash_password ---

func test_hash_password_deterministic() -> void:
	var h1: String = config._hash_password("test", "pass123")
	var h2: String = config._hash_password("test", "pass123")
	assert_eq(h1, h2)


func test_hash_password_different_slugs() -> void:
	var h1: String = config._hash_password("slug-a", "pass")
	var h2: String = config._hash_password("slug-b", "pass")
	assert_ne(h1, h2)


func test_hash_password_different_passwords() -> void:
	var h1: String = config._hash_password("test", "pass1")
	var h2: String = config._hash_password("test", "pass2")
	assert_ne(h1, h2)


# --- create_profile ---

func test_create_profile_fresh() -> void:
	var slug: String = config.create_profile("Work")
	assert_eq(slug, "work")
	var profiles: Array = config.get_profiles()
	assert_eq(profiles.size(), 2) # default + work
	assert_eq(profiles[1]["slug"], "work")
	assert_eq(profiles[1]["name"], "Work")
	assert_false(profiles[1]["has_password"])


func test_create_profile_with_password() -> void:
	var slug: String = config.create_profile("Secret", "pw123")
	var profiles: Array = config.get_profiles()
	var found := false
	for p in profiles:
		if p["slug"] == slug:
			found = true
			assert_true(p["has_password"])
	assert_true(found)


func test_create_profile_copy() -> void:
	# Add a server to the current config
	config.add_server("http://host:3000", "tok", "guild")
	var slug: String = config.create_profile(
		"Personal", "", true
	)
	# The copied config file should exist
	var cfg_path := "user://profiles/" + slug + "/config.cfg"
	assert_true(
		FileAccess.file_exists(cfg_path)
		or DirAccess.dir_exists_absolute(
			"user://profiles/" + slug
		)
	)


# --- delete_profile ---

func test_delete_profile_default_blocked() -> void:
	var result: bool = config.delete_profile("default")
	assert_false(result)
	var profiles: Array = config.get_profiles()
	assert_eq(profiles.size(), 1)


func test_delete_profile_removes_from_registry() -> void:
	config.create_profile("ToDelete")
	assert_eq(config.get_profiles().size(), 2)
	var result: bool = config.delete_profile("todelete")
	assert_true(result)
	assert_eq(config.get_profiles().size(), 1)


# --- rename_profile ---

func test_rename_profile() -> void:
	config.create_profile("OldName")
	config.rename_profile("oldname", "NewName")
	var profiles: Array = config.get_profiles()
	var found := false
	for p in profiles:
		if p["slug"] == "oldname":
			assert_eq(p["name"], "NewName")
			found = true
	assert_true(found)


# --- set_profile_password / verify_profile_password ---

func test_set_and_verify_password() -> void:
	config.create_profile("Protected")
	# No password yet — verify returns true
	assert_true(
		config.verify_profile_password("protected", "anything")
	)
	# Set password
	var result: bool = config.set_profile_password(
		"protected", "", "secret"
	)
	assert_true(result)
	# Verify correct password
	assert_true(
		config.verify_profile_password("protected", "secret")
	)
	# Verify wrong password
	assert_false(
		config.verify_profile_password("protected", "wrong")
	)


func test_set_password_wrong_old_fails() -> void:
	config.create_profile("Locked")
	config.set_profile_password("locked", "", "pw1")
	var result: bool = config.set_profile_password(
		"locked", "wrong-old", "pw2"
	)
	assert_false(result)
	# Original password still works
	assert_true(
		config.verify_profile_password("locked", "pw1")
	)


func test_remove_password() -> void:
	config.create_profile("Removable")
	config.set_profile_password("removable", "", "pw")
	# Remove by setting empty new password
	var result: bool = config.set_profile_password(
		"removable", "pw", ""
	)
	assert_true(result)
	# No password should mean verify returns true for anything
	assert_true(
		config.verify_profile_password("removable", "anything")
	)


# --- get_profiles / get_active_profile_slug ---

func test_get_profiles_ordered() -> void:
	config.create_profile("AAA")
	config.create_profile("BBB")
	var profiles: Array = config.get_profiles()
	assert_eq(profiles.size(), 3)
	assert_eq(profiles[0]["slug"], "default")
	assert_eq(profiles[1]["slug"], "aaa")
	assert_eq(profiles[2]["slug"], "bbb")


func test_get_active_profile_slug() -> void:
	assert_eq(config.get_active_profile_slug(), "default")


# --- move_profile_up / move_profile_down ---

func test_move_profile_up_down() -> void:
	config.create_profile("Alpha")
	config.create_profile("Beta")
	# Order: default, alpha, beta

	# Move beta up
	config.move_profile_up("beta")
	var profiles: Array = config.get_profiles()
	assert_eq(profiles[1]["slug"], "beta")
	assert_eq(profiles[2]["slug"], "alpha")

	# Move beta down (back to original position)
	config.move_profile_down("beta")
	profiles = config.get_profiles()
	assert_eq(profiles[1]["slug"], "alpha")
	assert_eq(profiles[2]["slug"], "beta")


func test_move_profile_up_at_top_no_op() -> void:
	config.create_profile("Top")
	# default is at index 0, moving up should be no-op
	config.move_profile_up("default")
	var profiles: Array = config.get_profiles()
	assert_eq(profiles[0]["slug"], "default")


func test_move_profile_down_at_bottom_no_op() -> void:
	config.create_profile("Bottom")
	# "bottom" is last, moving down should be no-op
	config.move_profile_down("bottom")
	var profiles: Array = config.get_profiles()
	assert_eq(
		profiles[profiles.size() - 1]["slug"], "bottom"
	)
