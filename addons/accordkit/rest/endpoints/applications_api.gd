class_name ApplicationsApi
extends RefCounted

## REST endpoint helpers for application management: creating applications,
## fetching and updating the current application, and resetting the bot token.

var _rest: AccordRest


func _init(rest: AccordRest) -> void:
	_rest = rest


## Creates a new application.
func create(data: Dictionary) -> RestResult:
	var result := await _rest.make_request("POST", "/applications", data)
	return result


## Fetches the current application's details.
func get_me() -> RestResult:
	var result := await _rest.make_request("GET", "/applications/@me")
	return result


## Updates the current application's settings.
func update_me(data: Dictionary) -> RestResult:
	var result := await _rest.make_request("PATCH", "/applications/@me", data)
	return result


## Resets the current application's bot token. The new token is returned
## in the response and the old token is immediately invalidated.
func reset_token() -> RestResult:
	var result := await _rest.make_request("POST", "/applications/@me/reset-token")
	return result
