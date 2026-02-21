class_name InteractionsApi
extends RefCounted

## REST endpoint helpers for application command and interaction response
## management: registering global and space-scoped commands, responding to
## interactions, editing original responses, and sending follow-ups.

var _rest: AccordRest


func _init(rest: AccordRest) -> void:
	_rest = rest


## Lists all global application commands.
func list_global_commands(app_id: String) -> RestResult:
	var result := await _rest.make_request("GET", "/applications/" + app_id + "/commands")
	return result


## Creates a new global application command.
func create_global_command(app_id: String, data: Dictionary) -> RestResult:
	var result := await _rest.make_request("POST", "/applications/" + app_id + "/commands", data)
	return result


## Fetches a single global application command by its ID.
func get_global_command(app_id: String, command_id: String) -> RestResult:
	var path := "/applications/" + app_id + "/commands/" + command_id
	var result := await _rest.make_request("GET", path)
	return result


## Updates an existing global application command.
func update_global_command(app_id: String, command_id: String, data: Dictionary) -> RestResult:
	var path := "/applications/" + app_id + "/commands/" + command_id
	var result := await _rest.make_request("PATCH", path, data)
	return result


## Deletes a global application command.
func delete_global_command(app_id: String, command_id: String) -> RestResult:
	var path := "/applications/" + app_id + "/commands/" + command_id
	var result := await _rest.make_request("DELETE", path)
	return result


## Overwrites all global application commands with the provided array.
## Commands not in the array are deleted.
func bulk_overwrite_global(app_id: String, data: Array) -> RestResult:
	var result := await _rest.make_request("PUT", "/applications/" + app_id + "/commands", data)
	return result


## Lists all application commands registered to a specific space.
func list_space_commands(app_id: String, space_id: String) -> RestResult:
	var path := (
		"/applications/" + app_id + "/spaces/"
		+ space_id + "/commands"
	)
	var result := await _rest.make_request("GET", path)
	return result


## Creates a new application command scoped to a specific space.
func create_space_command(app_id: String, space_id: String, data: Dictionary) -> RestResult:
	var path := (
		"/applications/" + app_id + "/spaces/"
		+ space_id + "/commands"
	)
	var result := await _rest.make_request("POST", path, data)
	return result


## Sends an initial response to an interaction. The data dictionary should
## contain "type" and optionally "data" with the response payload.
func respond(interaction_id: String, token: String, data: Dictionary) -> RestResult:
	var path := (
		"/interactions/" + interaction_id + "/" + token
		+ "/callback"
	)
	var result := await _rest.make_request("POST", path, data)
	return result


## Edits the original interaction response message.
func edit_original(app_id: String, token: String, data: Dictionary) -> RestResult:
	var path := (
		"/webhooks/" + app_id + "/" + token
		+ "/messages/@original"
	)
	var result := await _rest.make_request("PATCH", path, data)
	return result


## Deletes the original interaction response message.
func delete_original(app_id: String, token: String) -> RestResult:
	var path := (
		"/webhooks/" + app_id + "/" + token
		+ "/messages/@original"
	)
	var result := await _rest.make_request("DELETE", path)
	return result


## Sends a follow-up message to an interaction. Follow-ups can be sent
## for up to 15 minutes after the initial response.
func followup(app_id: String, token: String, data: Dictionary) -> RestResult:
	var result := await _rest.make_request("POST", "/webhooks/" + app_id + "/" + token, data)
	return result
