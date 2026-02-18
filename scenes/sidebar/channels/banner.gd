extends Control

@onready var banner_rect: ColorRect = $BannerRect
@onready var guild_name_label: Label = $GuildName

func setup(guild_data: Dictionary) -> void:
	guild_name_label.text = guild_data.get("name", "")
	guild_name_label.add_theme_font_size_override("font_size", 16)
	guild_name_label.add_theme_color_override("font_color", Color.WHITE)
	banner_rect.color = guild_data.get("icon_color", Color(0.184, 0.192, 0.212)).darkened(0.3)
