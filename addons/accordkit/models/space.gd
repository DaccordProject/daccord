class_name AccordSpace
extends RefCounted

## Discord guild (space) object.

var id: String
var name: String
var slug: String
var description = null
var icon = null
var banner = null
var splash = null
var owner_id: String = ""
var features: Array = []
var verification_level: String = "none"
var default_notifications: String = "all"
var explicit_content_filter: String = "disabled"
var roles: Array = []
var emojis: Array = []
var member_count = null
var presence_count = null
var max_members = null
var vanity_url_code = null
var preferred_locale: String = "en-US"
var afk_channel_id = null
var afk_timeout: int = 0
var system_channel_id = null
var rules_channel_id = null
var nsfw_level: String = "default"
var premium_tier: String = "none"
var premium_subscription_count: int = 0
var created_at: String = ""


static func from_dict(d: Dictionary) -> AccordSpace:
	var s := AccordSpace.new()
	s.id = str(d.get("id", ""))
	s.name = d.get("name", "")
	s.slug = d.get("slug", "")
	s.description = d.get("description", null)
	s.icon = d.get("icon", null)
	s.banner = d.get("banner", null)
	s.splash = d.get("splash", null)
	s.owner_id = str(d.get("owner_id", ""))
	s.features = d.get("features", [])
	s.verification_level = d.get("verification_level", "none")
	s.default_notifications = d.get("default_notifications", "all")
	s.explicit_content_filter = d.get("explicit_content_filter", "disabled")

	s.roles = []
	var raw_roles = d.get("roles", [])
	for r in raw_roles:
		if r is Dictionary:
			s.roles.append(AccordRole.from_dict(r))

	s.emojis = []
	var raw_emojis = d.get("emojis", [])
	for e in raw_emojis:
		if e is Dictionary:
			s.emojis.append(AccordEmoji.from_dict(e))

	s.member_count = d.get("member_count", null)
	s.presence_count = d.get("presence_count", null)
	s.max_members = d.get("max_members", null)
	s.vanity_url_code = d.get("vanity_url_code", null)
	s.preferred_locale = d.get("preferred_locale", "en-US")
	s.afk_channel_id = null
	var raw_afk = d.get("afk_channel_id", null)
	if raw_afk != null:
		s.afk_channel_id = str(raw_afk)
	s.afk_timeout = d.get("afk_timeout", 0)
	s.system_channel_id = null
	var raw_sys = d.get("system_channel_id", null)
	if raw_sys != null:
		s.system_channel_id = str(raw_sys)
	s.rules_channel_id = null
	var raw_rules = d.get("rules_channel_id", null)
	if raw_rules != null:
		s.rules_channel_id = str(raw_rules)
	s.nsfw_level = d.get("nsfw_level", "default")
	s.premium_tier = d.get("premium_tier", "none")
	s.premium_subscription_count = d.get("premium_subscription_count", 0)
	s.created_at = d.get("created_at", "")
	return s


func to_dict() -> Dictionary:
	var d := {
		"id": id,
		"name": name,
		"slug": slug,
		"owner_id": owner_id,
		"features": features,
		"verification_level": verification_level,
		"default_notifications": default_notifications,
		"explicit_content_filter": explicit_content_filter,
		"preferred_locale": preferred_locale,
		"afk_timeout": afk_timeout,
		"nsfw_level": nsfw_level,
		"premium_tier": premium_tier,
		"premium_subscription_count": premium_subscription_count,
		"created_at": created_at,
	}

	var role_dicts := []
	for r in roles:
		if r is AccordRole:
			role_dicts.append(r.to_dict())
	d["roles"] = role_dicts

	var emoji_dicts := []
	for e in emojis:
		if e is AccordEmoji:
			emoji_dicts.append(e.to_dict())
	d["emojis"] = emoji_dicts

	if description != null:
		d["description"] = description
	if icon != null:
		d["icon"] = icon
	if banner != null:
		d["banner"] = banner
	if splash != null:
		d["splash"] = splash
	if member_count != null:
		d["member_count"] = member_count
	if presence_count != null:
		d["presence_count"] = presence_count
	if max_members != null:
		d["max_members"] = max_members
	if vanity_url_code != null:
		d["vanity_url_code"] = vanity_url_code
	if afk_channel_id != null:
		d["afk_channel_id"] = afk_channel_id
	if system_channel_id != null:
		d["system_channel_id"] = system_channel_id
	if rules_channel_id != null:
		d["rules_channel_id"] = rules_channel_id
	return d
