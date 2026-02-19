class_name MessageViewBanner
extends RefCounted

var connection_banner: PanelContainer
var status_label: Label
var retry_button: Button
var _hide_timer: Timer

var _style_warning: StyleBoxFlat
var _style_error: StyleBoxFlat
var _style_success: StyleBoxFlat

var _get_guild_for_channel: Callable


func _init(
	banner: PanelContainer,
	p_status_label: Label,
	p_retry_button: Button,
	hide_timer: Timer,
	get_guild: Callable,
) -> void:
	connection_banner = banner
	status_label = p_status_label
	retry_button = p_retry_button
	_hide_timer = hide_timer
	_get_guild_for_channel = get_guild

	_style_warning = StyleBoxFlat.new()
	_style_warning.bg_color = Color(0.75, 0.55, 0.1, 0.9)
	_style_warning.set_content_margin_all(6)
	_style_warning.set_corner_radius_all(4)

	_style_error = StyleBoxFlat.new()
	_style_error.bg_color = Color(0.75, 0.2, 0.2, 0.9)
	_style_error.set_content_margin_all(6)
	_style_error.set_corner_radius_all(4)

	_style_success = StyleBoxFlat.new()
	_style_success.bg_color = Color(0.2, 0.65, 0.3, 0.9)
	_style_success.set_content_margin_all(6)
	_style_success.set_corner_radius_all(4)


func on_server_disconnected(
	guild_id: String, _code: int, _reason: String
) -> void:
	if guild_id != _get_guild_for_channel.call():
		return
	_hide_timer.stop()
	connection_banner.add_theme_stylebox_override("panel", _style_warning)
	status_label.text = "Connection lost. Reconnecting..."
	retry_button.visible = false
	connection_banner.visible = true


func on_server_reconnecting(
	guild_id: String, attempt: int, max_attempts: int
) -> void:
	if guild_id != _get_guild_for_channel.call():
		return
	_hide_timer.stop()
	connection_banner.add_theme_stylebox_override("panel", _style_warning)
	status_label.text = "Reconnecting... (attempt %d/%d)" % [
		attempt, max_attempts
	]
	retry_button.visible = false
	connection_banner.visible = true


func on_server_reconnected(guild_id: String) -> void:
	if guild_id != _get_guild_for_channel.call():
		return
	connection_banner.add_theme_stylebox_override("panel", _style_success)
	status_label.text = "Reconnected!"
	retry_button.visible = false
	connection_banner.visible = true
	_hide_timer.start()


func on_server_connection_failed(
	guild_id: String, reason: String
) -> void:
	if guild_id != _get_guild_for_channel.call():
		return
	_hide_timer.stop()
	connection_banner.add_theme_stylebox_override("panel", _style_error)
	status_label.text = "Connection failed: %s" % reason
	retry_button.visible = true
	connection_banner.visible = true


func on_retry_pressed() -> void:
	var guild_id: String = _get_guild_for_channel.call()
	var idx := Client.get_conn_index_for_guild(guild_id)
	if idx >= 0:
		connection_banner.add_theme_stylebox_override(
			"panel", _style_warning
		)
		status_label.text = "Reconnecting..."
		retry_button.visible = false
		Client._auto_reconnect_attempted.erase(idx)
		Client.reconnect_server(idx)
