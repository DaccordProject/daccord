class_name AccordCDN extends RefCounted

static var base_url: String = AccordConfig.DEFAULT_CDN_URL

static func _resolve(cdn_url: String) -> String:
	return cdn_url if not cdn_url.is_empty() else base_url

static func avatar(
	user_id: String, hash: String,
	format: String = "png", cdn_url: String = "",
) -> String:
	return (
		_resolve(cdn_url) + "/avatars/" + user_id
		+ "/" + hash + "." + format
	)

static func default_avatar(index: int, cdn_url: String = "") -> String:
	return (
		_resolve(cdn_url) + "/embed/avatars/"
		+ str(index) + ".png"
	)

static func space_icon(
	space_id: String, hash: String,
	format: String = "png", cdn_url: String = "",
) -> String:
	return (
		_resolve(cdn_url) + "/space-icons/" + space_id
		+ "/" + hash + "." + format
	)

static func space_banner(
	space_id: String, hash: String,
	format: String = "png", cdn_url: String = "",
) -> String:
	return (
		_resolve(cdn_url) + "/banners/" + space_id
		+ "/" + hash + "." + format
	)

static func emoji(
	emoji_id: String, format: String = "png",
	cdn_url: String = "",
) -> String:
	return (
		_resolve(cdn_url) + "/emojis/"
		+ emoji_id + "." + format
	)

static func attachment(
	channel_id: String, attachment_id: String,
	filename: String, cdn_url: String = "",
) -> String:
	return (
		_resolve(cdn_url) + "/attachments/" + channel_id
		+ "/" + attachment_id + "/" + filename
	)

static func sound(audio_url: String, cdn_url: String = "") -> String:
	if audio_url.begins_with("http://") or audio_url.begins_with("https://"):
		return audio_url
	return _resolve(cdn_url) + audio_url

static func is_animated(hash: String) -> bool:
	return hash.begins_with("a_")

static func auto_format(hash: String) -> String:
	return "gif" if is_animated(hash) else "png"
