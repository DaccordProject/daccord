extends GutTest

## Tests for the Updater semver parsing and comparison utilities.

var Updater := preload("res://scripts/autoload/updater.gd")


# ------------------------------------------------------------------
# parse_semver
# ------------------------------------------------------------------

func test_parse_basic_version() -> void:
	var r: Dictionary = Updater.parse_semver("1.2.3")
	assert_true(r["valid"])
	assert_eq(r["major"], 1)
	assert_eq(r["minor"], 2)
	assert_eq(r["patch"], 3)
	assert_eq(r["pre"], "")


func test_parse_with_v_prefix() -> void:
	var r: Dictionary = Updater.parse_semver("v0.1.0")
	assert_true(r["valid"])
	assert_eq(r["major"], 0)
	assert_eq(r["minor"], 1)
	assert_eq(r["patch"], 0)


func test_parse_with_prerelease() -> void:
	var r: Dictionary = Updater.parse_semver("2.0.0-beta.1")
	assert_true(r["valid"])
	assert_eq(r["major"], 2)
	assert_eq(r["minor"], 0)
	assert_eq(r["patch"], 0)
	assert_eq(r["pre"], "beta.1")


func test_parse_with_v_prefix_and_prerelease() -> void:
	var r: Dictionary = Updater.parse_semver("v1.0.0-rc.2")
	assert_true(r["valid"])
	assert_eq(r["pre"], "rc.2")


func test_parse_invalid_too_few_parts() -> void:
	var r: Dictionary = Updater.parse_semver("1.2")
	assert_false(r["valid"])


func test_parse_invalid_non_numeric() -> void:
	var r: Dictionary = Updater.parse_semver("a.b.c")
	assert_false(r["valid"])


func test_parse_empty_string() -> void:
	var r: Dictionary = Updater.parse_semver("")
	assert_false(r["valid"])


func test_parse_strips_whitespace() -> void:
	var r: Dictionary = Updater.parse_semver("  1.0.0  ")
	assert_true(r["valid"])
	assert_eq(r["major"], 1)


# ------------------------------------------------------------------
# compare_semver
# ------------------------------------------------------------------

func test_compare_equal() -> void:
	assert_eq(Updater.compare_semver("1.0.0", "1.0.0"), 0)


func test_compare_major_greater() -> void:
	assert_eq(Updater.compare_semver("2.0.0", "1.9.9"), 1)


func test_compare_major_less() -> void:
	assert_eq(Updater.compare_semver("1.0.0", "2.0.0"), -1)


func test_compare_minor_greater() -> void:
	assert_eq(Updater.compare_semver("1.2.0", "1.1.9"), 1)


func test_compare_minor_less() -> void:
	assert_eq(Updater.compare_semver("1.0.0", "1.1.0"), -1)


func test_compare_patch_greater() -> void:
	assert_eq(Updater.compare_semver("1.0.2", "1.0.1"), 1)


func test_compare_patch_less() -> void:
	assert_eq(Updater.compare_semver("1.0.0", "1.0.1"), -1)


func test_compare_release_beats_prerelease() -> void:
	# 1.0.0 > 1.0.0-beta
	assert_eq(Updater.compare_semver("1.0.0", "1.0.0-beta"), 1)


func test_compare_prerelease_less_than_release() -> void:
	# 1.0.0-beta < 1.0.0
	assert_eq(Updater.compare_semver("1.0.0-beta", "1.0.0"), -1)


func test_compare_prerelease_lexicographic() -> void:
	# alpha < beta lexicographically
	assert_eq(Updater.compare_semver("1.0.0-alpha", "1.0.0-beta"), -1)
	assert_eq(Updater.compare_semver("1.0.0-beta", "1.0.0-alpha"), 1)


func test_compare_prerelease_equal() -> void:
	assert_eq(Updater.compare_semver("1.0.0-rc.1", "1.0.0-rc.1"), 0)


func test_compare_with_v_prefix() -> void:
	assert_eq(Updater.compare_semver("v1.1.0", "v1.0.0"), 1)


func test_compare_invalid_returns_zero() -> void:
	assert_eq(Updater.compare_semver("bad", "1.0.0"), 0)
	assert_eq(Updater.compare_semver("1.0.0", "bad"), 0)


# ------------------------------------------------------------------
# is_newer
# ------------------------------------------------------------------

func test_is_newer_true() -> void:
	assert_true(Updater.is_newer("1.1.0", "1.0.0"))


func test_is_newer_false_equal() -> void:
	assert_false(Updater.is_newer("1.0.0", "1.0.0"))


func test_is_newer_false_older() -> void:
	assert_false(Updater.is_newer("0.9.0", "1.0.0"))


func test_is_newer_prerelease_not_newer_than_release() -> void:
	assert_false(Updater.is_newer("1.0.0-beta", "1.0.0"))


func test_is_newer_release_newer_than_prerelease() -> void:
	assert_true(Updater.is_newer("1.0.0", "1.0.0-beta"))


func test_is_newer_next_version_prerelease() -> void:
	# 1.1.0-beta is newer than 1.0.0 (higher minor)
	assert_true(Updater.is_newer("1.1.0-beta", "1.0.0"))
