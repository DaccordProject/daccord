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


# ------------------------------------------------------------------
# _parse_release
# ------------------------------------------------------------------

func test_parse_release_valid_with_linux_asset() -> void:
	var data := {
		"tag_name": "v1.2.0",
		"html_url": "https://github.com/DaccordProject/daccord/releases/tag/v1.2.0",
		"body": "Release notes here",
		"prerelease": false,
		"assets": [
			{
				"name": "daccord-linux-x86_64.tar.gz",
				"browser_download_url": "https://github.com/download/linux.tar.gz",
				"size": 50000000,
			},
			{
				"name": "daccord-windows-x86_64.zip",
				"browser_download_url": "https://github.com/download/win.zip",
				"size": 60000000,
			},
		],
	}
	var r: Dictionary = Updater._parse_release(data)
	assert_eq(r["version"], "1.2.0")
	assert_eq(r["tag"], "v1.2.0")
	assert_eq(r["release_url"], "https://github.com/DaccordProject/daccord/releases/tag/v1.2.0")
	assert_eq(r["notes"], "Release notes here")
	assert_eq(r["prerelease"], false)
	assert_eq(r["download_url"], "https://github.com/download/linux.tar.gz")
	assert_eq(r["download_size"], 50000000)


func test_parse_release_missing_tag() -> void:
	var data := {
		"html_url": "https://example.com",
		"body": "notes",
	}
	var r: Dictionary = Updater._parse_release(data)
	assert_true(r.is_empty())


func test_parse_release_invalid_tag() -> void:
	var data := {
		"tag_name": "not-a-version",
		"html_url": "https://example.com",
	}
	var r: Dictionary = Updater._parse_release(data)
	assert_true(r.is_empty())


func test_parse_release_no_linux_asset() -> void:
	var data := {
		"tag_name": "v2.0.0",
		"html_url": "https://example.com/release",
		"body": "",
		"prerelease": false,
		"assets": [
			{
				"name": "daccord-windows-x86_64.zip",
				"browser_download_url": "https://example.com/win.zip",
				"size": 40000000,
			},
		],
	}
	var r: Dictionary = Updater._parse_release(data)
	assert_eq(r["version"], "2.0.0")
	assert_eq(r["download_url"], "")
	assert_eq(r["download_size"], 0)


# ------------------------------------------------------------------
# is_downloading / is_update_ready (instance state)
# ------------------------------------------------------------------

func test_is_downloading_default_false() -> void:
	var instance := Updater.new()
	assert_false(instance.is_downloading())
	instance.free()


func test_is_update_ready_default_false() -> void:
	var instance := Updater.new()
	assert_false(instance.is_update_ready())
	instance.free()


func test_parse_release_prerelease_tag() -> void:
	var data := {
		"tag_name": "v1.3.0-beta.1",
		"html_url": "https://example.com/pre",
		"body": "Beta notes",
		"prerelease": true,
		"assets": [
			{
				"name": "daccord-linux-x86_64.tar.gz",
				"browser_download_url": "https://example.com/linux-beta.tar.gz",
				"size": 48000000,
			},
		],
	}
	var r: Dictionary = Updater._parse_release(data)
	assert_eq(r["version"], "1.3.0-beta.1")
	assert_eq(r["prerelease"], true)
	assert_eq(r["download_url"], "https://example.com/linux-beta.tar.gz")
