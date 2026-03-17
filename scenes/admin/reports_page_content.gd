extends VBoxContainer

## Content layout for the reports tab in server management.

@onready var filter_option: OptionButton = $FilterRow/FilterOption
@onready var error_label: Label = $ErrorLabel
@onready var empty_label: Label = $EmptyLabel
@onready var reports_list: VBoxContainer = $ReportsList
@onready var load_more_btn: Button = $LoadMoreButton


func _ready() -> void:
	$FilterRow/FilterLabel.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	empty_label.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	error_label.add_theme_color_override(
		"font_color", ThemeManager.get_color("error")
	)
	ThemeManager.style_button(
		load_more_btn, "secondary_button",
		"secondary_button_hover",
		"secondary_button_pressed", 4, [16, 6, 16, 6]
	)

	filter_option.add_item(tr("All"), 0)
	filter_option.add_item(tr("Pending"), 1)
	filter_option.add_item(tr("Actioned"), 2)
	filter_option.add_item(tr("Dismissed"), 3)
