extends Node

## Semver parsing and comparison utilities for the auto-update system.
## Will eventually handle GitHub Releases API checks and download management.


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
