class_name AuthApi
extends RefCounted

## REST endpoint helpers for authentication routes (register and login).
## These endpoints are unauthenticated -- the server returns a bearer token
## on success.

var _rest: AccordRest


func _init(rest: AccordRest) -> void:
	_rest = rest


## Registers a new user account.
## data should contain: { "username": String, "password": String }
## and optionally "display_name": String.
## Returns RestResult with data = { "user": AccordUser, "token": String }.
func register(data: Dictionary) -> RestResult:
	var result := await _rest.make_request("POST", "/auth/register", data)
	if result.ok and result.data is Dictionary:
		result.data = _parse_auth_response(result.data)
	return result


## Logs in with existing credentials.
## data should contain: { "username": String, "password": String }.
## Returns RestResult with data = { "user": AccordUser, "token": String }.
func login(data: Dictionary) -> RestResult:
	var result := await _rest.make_request("POST", "/auth/login", data)
	if result.ok and result.data is Dictionary:
		result.data = _parse_auth_response(result.data)
	return result


## Changes the current user's password.
## data should contain: { "current_password": String, "new_password": String }.
func change_password(data: Dictionary) -> RestResult:
	return await _rest.make_request("POST", "/auth/password", data)


## Enables two-factor authentication. Returns a TOTP secret.
func enable_2fa(data: Dictionary) -> RestResult:
	return await _rest.make_request("POST", "/auth/2fa/enable", data)


## Verifies a 2FA code during setup.
## data should contain: { "code": String }.
func verify_2fa(data: Dictionary) -> RestResult:
	return await _rest.make_request("POST", "/auth/2fa/verify", data)


## Disables two-factor authentication.
## data should contain: { "password": String }.
func disable_2fa(data: Dictionary) -> RestResult:
	return await _rest.make_request("POST", "/auth/2fa/disable", data)


## Retrieves backup codes for 2FA.
func get_backup_codes() -> RestResult:
	return await _rest.make_request("GET", "/auth/2fa/backup-codes")


## Parses the auth response envelope into { "user": AccordUser, "token": String }.
func _parse_auth_response(d: Dictionary) -> Dictionary:
	var parsed := {}
	if d.has("user") and d["user"] is Dictionary:
		parsed["user"] = AccordUser.from_dict(d["user"])
	if d.has("token"):
		parsed["token"] = str(d["token"])
	return parsed
