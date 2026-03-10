class_name AuthApi
extends EndpointBase

## REST endpoint helpers for authentication routes (register and login).
## These endpoints are unauthenticated -- the server returns a bearer token
## on success.


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
## Returns RestResult with data = { "user": AccordUser, "token": String }
## OR data = { "mfa_required": true, "ticket": String } when 2FA is enabled.
func login(data: Dictionary) -> RestResult:
	var result := await _rest.make_request("POST", "/auth/login", data)
	if result.ok and result.data is Dictionary:
		# Don't parse as auth response if MFA is required
		if not result.data.get("mfa_required", false):
			result.data = _parse_auth_response(result.data)
	return result


## Completes MFA login with a TOTP code or backup code.
## data should contain: { "ticket": String, "code": String }.
## Returns RestResult with data = { "user": AccordUser, "token": String }.
func login_mfa(data: Dictionary) -> RestResult:
	var result := await _rest.make_request(
		"POST", "/auth/login/mfa", data
	)
	if result.ok and result.data is Dictionary:
		result.data = _parse_auth_response(result.data)
	return result


## Requests a short-lived guest token for anonymous read-only access.
## No credentials required. The server returns a token scoped to public
## channels with allow_anonymous_read = true.
## Returns RestResult with data = { "token": String, "expires_at": String, "space_id": String }.
func guest() -> RestResult:
	return await _rest.make_request("POST", "/auth/guest")


## Changes the current user's password.
## data should contain: { "old_password": String, "new_password": String }.
## Clears force_password_reset flag and revokes all other sessions.
func change_password(data: Dictionary) -> RestResult:
	return await _rest.make_request("POST", "/auth/change-password", data)


## Enables two-factor authentication. Returns a TOTP secret and otpauth URI.
## data should contain: { "password": String }.
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


## Regenerates backup codes for 2FA.
## data should contain: { "password": String }.
func regenerate_backup_codes(data: Dictionary) -> RestResult:
	return await _rest.make_request(
		"POST", "/auth/2fa/backup-codes", data
	)


## Revokes all sessions for the current user.
func revoke_all_sessions() -> RestResult:
	return await _rest.make_request(
		"POST", "/auth/sessions/revoke-all"
	)


## Parses the auth response envelope into { "user": AccordUser, "token": String }.
## Preserves force_password_reset flag when present.
func _parse_auth_response(d: Dictionary) -> Dictionary:
	var parsed := {}
	if d.has("user") and d["user"] is Dictionary:
		parsed["user"] = AccordUser.from_dict(d["user"])
	if d.has("token"):
		parsed["token"] = str(d["token"])
	if d.get("force_password_reset", false):
		parsed["force_password_reset"] = true
	return parsed
