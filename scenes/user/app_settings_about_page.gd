extends RefCounted

## About settings page — app info and open source credits.

const SettingsBase := preload("res://scenes/user/settings_base.gd")

var _page_vbox: Callable
var _section_label: Callable


func _init(
	_host: Control, page_vbox: Callable, section_label: Callable,
) -> void:
	_page_vbox = page_vbox
	_section_label = section_label


func build() -> VBoxContainer:
	var vbox: VBoxContainer = _page_vbox.call("About")

	# App info
	var app_label := Label.new()
	app_label.text = "daccord v%s" % Client.app_version
	app_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(app_label)

	var mit_label := Label.new()
	mit_label.text = "MIT License — Copyright (c) 2025 daccord-projects"
	mit_label.add_theme_font_size_override("font_size", 12)
	mit_label.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	vbox.add_child(mit_label)

	vbox.add_child(HSeparator.new())

	# Open source credits
	vbox.add_child(_section_label.call("OPEN SOURCE CREDITS"))

	var credits := [
		[
			"Twemoji",
			"Emoji graphics used throughout the app.",
			"Copyright (c) Twitter, Inc. and other contributors",
			"CC BY 4.0 (graphics), MIT (code)",
			"https://github.com/twitter/twemoji",
		],
		[
			"godot-livekit",
			"GDExtension for real-time voice and video.",
			"Copyright (c) NodotProject",
			"MIT License",
			"https://github.com/NodotProject/godot-livekit",
		],
		[
			"LiveKit Client SDK",
			"Real-time communication platform.",
			"Copyright (c) LiveKit, Inc.",
			"Apache License 2.0",
			"https://github.com/livekit/client-sdk-cpp",
		],
		[
			"Sentry SDK for Godot",
			"Error reporting and crash monitoring.",
			"Copyright (c) Sentry",
			"MIT License",
			"https://github.com/getsentry/sentry-godot",
		],
		[
			"GUT (Godot Unit Test)",
			"Testing framework.",
			"Copyright (c) Tom \"Butch\" Wesley",
			"MIT License",
			"https://github.com/bitwes/Gut",
		],
		[
			"Godot Sandbox",
			"Safe modding and sandboxed scripting for Godot.",
			"Copyright (c) 2024, Alf-André Walla",
			"BSD 3-Clause License",
			"https://github.com/libriscv/godot-sandbox",
		],
	]

	for entry in credits:
		var card: PanelContainer = _build_credit_card(
			entry[0], entry[1], entry[2], entry[3], entry[4]
		)
		vbox.add_child(card)

	return vbox


func _build_credit_card(
	title: String, description: String, copyright: String,
	license_text: String, url: String,
) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(
		"panel", ThemeManager.make_flat_style("input_bg", 6)
	)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var card_vbox := VBoxContainer.new()
	card_vbox.add_theme_constant_override("separation", 4)
	margin.add_child(card_vbox)

	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 14)
	card_vbox.add_child(title_label)

	var desc_label := Label.new()
	desc_label.text = description
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_vbox.add_child(desc_label)

	var copy_label := Label.new()
	copy_label.text = copyright
	copy_label.add_theme_font_size_override("font_size", 11)
	copy_label.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	card_vbox.add_child(copy_label)

	var license_label := Label.new()
	license_label.text = license_text
	license_label.add_theme_font_size_override("font_size", 11)
	license_label.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	card_vbox.add_child(license_label)

	var link := LinkButton.new()
	link.text = url
	link.uri = url
	link.add_theme_font_size_override("font_size", 11)
	link.add_theme_color_override(
		"font_color", ThemeManager.get_color("link")
	)
	card_vbox.add_child(link)

	return panel
