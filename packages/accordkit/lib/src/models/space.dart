import '../utils/json_utils.dart';
import 'emoji.dart';
import 'role.dart';

/// A space (server/guild).
class AccordSpace {
  String id;
  String name;
  String slug;
  String? description;
  Object? icon;
  Object? banner;
  Object? splash;
  String ownerId;
  List<dynamic> features;
  bool public;
  bool allowGuestAccess;
  String verificationLevel;
  String defaultNotifications;
  String explicitContentFilter;
  List<AccordRole> roles;
  List<AccordEmoji> emojis;
  Object? memberCount;
  Object? presenceCount;
  Object? maxMembers;
  Object? vanityUrlCode;
  String preferredLocale;
  String? afkChannelId;
  int afkTimeout;
  String? systemChannelId;
  String? rulesChannelId;
  String nsfwLevel;
  String premiumTier;
  int premiumSubscriptionCount;
  String createdAt;

  AccordSpace({
    this.id = '',
    this.name = '',
    this.slug = '',
    this.description,
    this.icon,
    this.banner,
    this.splash,
    this.ownerId = '',
    List<dynamic>? features,
    this.public = false,
    this.allowGuestAccess = true,
    this.verificationLevel = 'none',
    this.defaultNotifications = 'all',
    this.explicitContentFilter = 'disabled',
    List<AccordRole>? roles,
    List<AccordEmoji>? emojis,
    this.memberCount,
    this.presenceCount,
    this.maxMembers,
    this.vanityUrlCode,
    this.preferredLocale = 'en-US',
    this.afkChannelId,
    this.afkTimeout = 0,
    this.systemChannelId,
    this.rulesChannelId,
    this.nsfwLevel = 'default',
    this.premiumTier = 'none',
    this.premiumSubscriptionCount = 0,
    this.createdAt = '',
  })  : features = features ?? [],
        roles = roles ?? [],
        emojis = emojis ?? [];

  factory AccordSpace.fromJson(Map<String, dynamic> d) {
    final s = AccordSpace(
      id: asString(d['id']),
      name: asString(d['name']),
      slug: asString(d['slug']),
      description: d['description'] as String?,
      icon: d['icon'],
      banner: d['banner'],
      splash: d['splash'],
      ownerId: asString(d['owner_id']),
      features: asList(d['features']) ?? [],
      public: asBool(d['public']),
      allowGuestAccess: asBool(d['allow_guest_access'], true),
      verificationLevel: asString(d['verification_level'], 'none'),
      defaultNotifications: asString(d['default_notifications'], 'all'),
      explicitContentFilter: asString(d['explicit_content_filter'], 'disabled'),
      memberCount: d['member_count'],
      presenceCount: d['presence_count'],
      maxMembers: d['max_members'],
      vanityUrlCode: d['vanity_url_code'],
      preferredLocale: asString(d['preferred_locale'], 'en-US'),
      afkChannelId: asStringOrNull(d['afk_channel_id']),
      afkTimeout: asInt(d['afk_timeout']),
      systemChannelId: asStringOrNull(d['system_channel_id']),
      rulesChannelId: asStringOrNull(d['rules_channel_id']),
      nsfwLevel: asString(d['nsfw_level'], 'default'),
      premiumTier: asString(d['premium_tier'], 'none'),
      premiumSubscriptionCount: asInt(d['premium_subscription_count']),
      createdAt: asString(d['created_at']),
    );

    for (final r in asList(d['roles']) ?? const []) {
      final rm = asMap(r);
      if (rm != null) s.roles.add(AccordRole.fromJson(rm));
    }
    for (final e in asList(d['emojis']) ?? const []) {
      final em = asMap(e);
      if (em != null) s.emojis.add(AccordEmoji.fromJson(em));
    }
    return s;
  }

  Map<String, dynamic> toJson() {
    final d = <String, dynamic>{
      'id': id,
      'name': name,
      'slug': slug,
      'owner_id': ownerId,
      'features': features,
      'public': public,
      'allow_guest_access': allowGuestAccess,
      'verification_level': verificationLevel,
      'default_notifications': defaultNotifications,
      'explicit_content_filter': explicitContentFilter,
      'preferred_locale': preferredLocale,
      'afk_timeout': afkTimeout,
      'nsfw_level': nsfwLevel,
      'premium_tier': premiumTier,
      'premium_subscription_count': premiumSubscriptionCount,
      'created_at': createdAt,
      'roles': toJsonList(roles),
      'emojis': toJsonList(emojis),
    };
    if (description != null) d['description'] = description;
    if (icon != null) d['icon'] = icon;
    if (banner != null) d['banner'] = banner;
    if (splash != null) d['splash'] = splash;
    if (memberCount != null) d['member_count'] = memberCount;
    if (presenceCount != null) d['presence_count'] = presenceCount;
    if (maxMembers != null) d['max_members'] = maxMembers;
    if (vanityUrlCode != null) d['vanity_url_code'] = vanityUrlCode;
    if (afkChannelId != null) d['afk_channel_id'] = afkChannelId;
    if (systemChannelId != null) d['system_channel_id'] = systemChannelId;
    if (rulesChannelId != null) d['rules_channel_id'] = rulesChannelId;
    return d;
  }
}
