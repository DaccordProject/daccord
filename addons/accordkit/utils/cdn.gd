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
	return resolve_path(audio_url, cdn_url)

## Resolves a server-returned CDN path (e.g. "/cdn/avatars/123.png")
## to a full URL. Handles both absolute URLs and relative /cdn/ paths.
static func resolve_path(
	path: String, cdn_url: String = "",
) -> String:
	if path.begins_with("http://") or path.begins_with("https://"):
		return path
	if path.begins_with("/cdn/"):
		return _resolve(cdn_url) + path.substr(4)
	if path.begins_with("/"):
		return _resolve(cdn_url) + path
	return _resolve(cdn_url) + "/" + path

## Builds a data URI from raw file bytes and a file path.
## Returns "data:image/{ext};base64,{encoded}" suitable for
## the server's avatar/icon/banner upload fields.
static func build_data_uri(
	bytes: PackedByteArray, file_path: String,
) -> String:
	var ext: String = file_path.get_extension().to_lower()
	var mime: String
	match ext:
		"jpg", "jpeg":
			mime = "image/jpeg"
		"webp":
			mime = "image/webp"
		"gif":
			mime = "image/gif"
		_:
			mime = "image/png"
	return "data:" + mime + ";base64," + Marshalls.raw_to_base64(bytes)

static func is_animated(hash: String) -> bool:
	return hash.begins_with("a_")

static func auto_format(hash: String) -> String:
	return "gif" if is_animated(hash) else "png"
