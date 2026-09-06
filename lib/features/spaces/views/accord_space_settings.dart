import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/shared/components/section_header.dart';
import 'package:bonfire/shared/components/ticker_aware_circle_avatar.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/text_prompt_dialog.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/permissions.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/spaces/utils/space_display.dart';
import 'package:bonfire/features/spaces/views/accord_audit_log.dart';
import 'package:bonfire/features/spaces/views/accord_ban_list.dart';
import 'package:bonfire/features/spaces/views/accord_emoji_management.dart';
import 'package:bonfire/features/spaces/views/accord_reports.dart';
import 'package:bonfire/features/spaces/views/accord_role_management.dart';
import 'package:bonfire/features/spaces/views/accord_soundboard.dart';
import 'package:bonfire/features/spaces/views/accord_transfer_ownership.dart';
import 'package:bonfire/shared/components/image_crop_dialog.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'accord_space_settings_form.dart';
part 'accord_space_settings_management.dart';
part 'accord_space_settings_layout.dart';

/// Opens the space settings screen for [spaceId]. Mirrors the client
/// [AccordSettingsScreen]: a full-screen route with section-grouped tiles.
/// Sections are permission-gated: the banner/overview editor needs
/// `manage_space`, the roles entry needs `manage_roles`, etc.
Future<void> showAccordSpaceSettings(
  BuildContext context, {
  required String spaceId,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => _SpaceSettings(spaceId: spaceId)),
  );
}

/// Space-level option presets, matching the reference client's space-settings
/// dialog. The right-hand value is the wire string sent to `spaces.update`.
const _verificationLevels = <({String label, String value})>[
  (label: 'None', value: 'none'),
  (label: 'Low', value: 'low'),
  (label: 'Medium', value: 'medium'),
  (label: 'High', value: 'high'),
];
const _notificationLevels = <({String label, String value})>[
  (label: 'All messages', value: 'all'),
  (label: 'Only @mentions', value: 'mentions'),
];
const _nsfwLevels = <({String label, String value})>[
  (label: 'Default', value: 'default'),
  (label: 'Moderate', value: 'moderate'),
  (label: 'Explicit', value: 'explicit'),
];
const _contentFilters = <({String label, String value})>[
  (label: 'Disabled', value: 'disabled'),
  (label: 'Members without roles', value: 'no_role'),
  (label: 'Everyone', value: 'everyone'),
];

class _SpaceSettings extends ConsumerStatefulWidget {
  const _SpaceSettings({required this.spaceId});

  final String spaceId;

  @override
  ConsumerState<_SpaceSettings> createState() => _SpaceSettingsState();
}

class _SpaceSettingsState extends ConsumerState<_SpaceSettings> {
  bool _busy = false;
  String? _error;

  // Draft state for the consolidated overview/settings form. Initialized from
  // the space the first time it's available (see [_ensureInitialized]) and
  // flushed in one `spaces.update` on Save.
  final TextEditingController _name = TextEditingController();
  final TextEditingController _description = TextEditingController();
  String _verification = 'none';
  String _notifications = 'all';
  String _nsfw = 'default';
  String _contentFilter = 'disabled';
  bool _public = false;
  bool _guestAccess = true;
  String? _rulesChannelId;
  String? _systemChannelId;
  String? _pendingIconDataUri;
  bool _iconRemoved = false;
  bool _formInitialized = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  /// Seeds the draft form from [space] once. Channel pickers later reconcile
  /// against the loaded channel list, so an id that's no longer valid resets to
  /// "None".
  void _ensureInitialized(AccordSpace space) {
    if (_formInitialized) return;
    _formInitialized = true;
    _name.text = space.name;
    _description.text = space.description ?? '';
    _verification = space.verificationLevel;
    _notifications = space.defaultNotifications;
    _nsfw = space.nsfwLevel;
    _contentFilter = space.explicitContentFilter;
    _public = space.public;
    _guestAccess = space.allowGuestAccess;
    _rulesChannelId = space.rulesChannelId;
    _systemChannelId = space.systemChannelId;
  }

  AccordClient? get _client => ref.accordClient;

  Set<String> _perms() {
    final space = ref
        .read(spacesControllerProvider)
        ?.firstWhereOrNull((s) => s.id == widget.spaceId);
    return ref.readAccordPermissions(space, widget.spaceId);
  }

  Future<void> _update(Map<String, dynamic> body, String failure) async {
    final client = _client;
    if (client == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await client.spaces.update(widget.spaceId, body);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!result.ok) _error = result.errorOr(failure);
    });
    final space = result.data;
    if (result.ok && space is AccordSpace) {
      ref.read(spacesControllerProvider.notifier).upsertSpace(space);
    }
  }

  Future<void> _pickBanner() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = picked?.files.firstOrNull;
    if (file?.bytes == null || !mounted) return;
    final cropped = await showImageCropDialog(
      context,
      imageBytes: file!.bytes!,
      aspectRatio: 16 / 9,
      title: 'Crop banner',
    );
    if (cropped == null) return;
    final dataUri = AccordCDN.buildDataUri(cropped, 'banner.png');
    await _update({'banner': dataUri}, 'Failed to update banner');
  }

  Future<void> _removeBanner() =>
      _update({'banner': null}, 'Failed to remove banner');

  Future<void> _pickIcon() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = picked?.files.firstOrNull;
    if (file?.bytes == null || !mounted) return;
    final cropped = await showImageCropDialog(
      context,
      imageBytes: file!.bytes!,
      aspectRatio: 1,
      circular: true,
      title: 'Crop icon',
    );
    if (cropped == null) return;
    setState(() {
      _pendingIconDataUri = AccordCDN.buildDataUri(cropped, 'icon.png');
      _iconRemoved = false;
    });
  }

  void _markIconRemoved() {
    setState(() {
      _pendingIconDataUri = null;
      _iconRemoved = true;
    });
  }

  /// Flushes the whole overview/settings form in one `spaces.update`. Icon is
  /// only sent when it was changed (uploaded or removed) this session.
  Future<void> _saveSettings() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    final body = <String, dynamic>{
      'name': name,
      'description': _description.text.trim(),
      'verification_level': _verification,
      'default_notifications': _notifications,
      'nsfw_level': _nsfw,
      'explicit_content_filter': _contentFilter,
      'public': _public,
      'allow_guest_access': _guestAccess,
      'rules_channel_id': _rulesChannelId,
      'system_channel_id': _systemChannelId,
    };
    if (_pendingIconDataUri != null) {
      body['icon'] = _pendingIconDataUri;
    } else if (_iconRemoved) {
      body['icon'] = null;
    }
    await _update(body, 'Failed to save settings');
    if (mounted && _error == null) {
      setState(() {
        _pendingIconDataUri = null;
        _iconRemoved = false;
      });
    }
  }

  /// Deletes the space after a typed confirmation (owner only). On success the
  /// dialog closes; the gateway `space.delete` event prunes the rail.
  Future<void> _deleteSpace(String spaceName) async {
    final client = _client;
    if (client == null) return;
    final confirmController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final canDelete = confirmController.text.trim() == spaceName.trim();
          return AlertDialog(
            title: const Text('Delete space'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'This permanently deletes "$spaceName" and all of its '
                  'channels and messages. This cannot be undone.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmController,
                  autofocus: true,
                  onChanged: (_) => setLocal(() {}),
                  decoration: InputDecoration(
                    labelText: 'Type the space name to confirm',
                    hintText: spaceName,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                ),
                onPressed: canDelete ? () => Navigator.of(ctx).pop(true) : null,
                child: const Text('Delete'),
              ),
            ],
          );
        },
      ),
    );
    confirmController.dispose();
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await client.spaces.delete(widget.spaceId);
    if (!mounted) return;
    if (!result.ok) {
      setState(() {
        _busy = false;
        _error = result.errorOr('Failed to delete space');
      });
      return;
    }
    ref.read(spacesControllerProvider.notifier).removeSpace(widget.spaceId);
    if (mounted) Navigator.of(context).pop();
  }

  /// Lets the user set or clear their own nickname in this space. Calls
  /// `members.update` with `{nickname: ...}` and mirrors the result into the
  /// member cache so every roster/message row picks it up immediately.
  Future<void> _editOwnNickname() async {
    final client = _client;
    final currentUserId = ref.readUserId();
    if (client == null || currentUserId == null) return;
    final members = ref.read(accordMembersControllerProvider(ref.readActiveServerKey() ?? '', widget.spaceId));
    final me = members?[currentUserId];
    final initial = me?.nickname ?? '';
    final next = (await showTextPromptDialog(
      context,
      title: 'Change nickname',
      label: 'Nickname',
      hintText: 'Leave empty to reset to your display name',
      initial: initial,
      resetLabel: initial.isNotEmpty ? 'Reset' : null,
    ))?.trim();
    if (next == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await client.members.update(widget.spaceId, currentUserId, {
      'nickname': next.isEmpty ? null : next,
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result.ok) {
      setState(() => _error = result.errorOr('Failed to update nickname'));
      return;
    }
    final updated = result.data;
    if (updated is AccordMember) {
      ref
          .read(accordMembersControllerProvider(ref.readActiveServerKey() ?? '', widget.spaceId).notifier)
          .upsertMember(updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final space = ref.watch(
      spacesControllerProvider.select(
        (s) => s?.firstWhereOrNull((sp) => sp.id == widget.spaceId),
      ),
    );
    final cdnUrl = ref.watchCdnUrl();
    final perms = _perms();
    final canManageSpace = accordHasPermission(
      perms,
      AccordPermission.manageSpace,
    );
    final canManageRoles = accordHasPermission(
      perms,
      AccordPermission.manageRoles,
    );
    final canViewAuditLog = accordHasPermission(
      perms,
      AccordPermission.viewAuditLog,
    );
    final currentUserId = ref.watchUserId();
    final isOwner =
        space != null &&
        currentUserId != null &&
        space.ownerId == currentUserId;
    final canModerate = accordHasPermission(perms, AccordPermission.banMembers);
    final canManageEmojis = accordHasPermission(
      perms,
      AccordPermission.manageEmojis,
    );
    final canUseSoundboard = accordHasPermission(
      perms,
      AccordPermission.useSoundboard,
    );
    final canManageSoundboard = accordHasPermission(
      perms,
      AccordPermission.manageSoundboard,
    );
    final bannerUrl = space == null
        ? null
        : accordSpaceBannerUrl(space, cdnUrl);
    if (space != null) _ensureInitialized(space);
    final iconUrl = space == null ? null : accordSpaceIconUrl(space, cdnUrl);
    // Text channels usable as rules/system targets. Reconcile the drafted ids
    // against the live list so a stale id falls back to "None".
    final textChannels =
        (ref.watch(accordChannelsControllerProvider(ref.readActiveServerKey() ?? '', widget.spaceId)) ??
                const <AccordChannel>[])
            .where((c) => c.type == 'text')
            .toList();
    final channelIds = textChannels.map((c) => c.id).toSet();
    final rulesValue = channelIds.contains(_rulesChannelId)
        ? _rulesChannelId
        : null;
    final systemValue = channelIds.contains(_systemChannelId)
        ? _systemChannelId
        : null;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.foreground,
        title: Text(space?.name ?? 'Space settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _AdaptiveSettingsBody(
        form: [
          _BannerSection(
            bannerUrl: bannerUrl,
            canManage: canManageSpace,
            busy: _busy,
            onPick: _pickBanner,
            onRemove: _removeBanner,
          ),
          if (canManageSpace) ...[
            const Divider(height: 24),
            _OverviewSection(
              nameController: _name,
              descriptionController: _description,
              iconUrl: iconUrl,
              pendingIconDataUri: _pendingIconDataUri,
              iconRemoved: _iconRemoved,
              busy: _busy,
              onPickIcon: _pickIcon,
              onRemoveIcon: _markIconRemoved,
            ),
            const Divider(height: 24),
            _ModerationSection(
              verification: _verification,
              notifications: _notifications,
              nsfw: _nsfw,
              contentFilter: _contentFilter,
              isPublic: _public,
              guestAccess: _guestAccess,
              busy: _busy,
              onVerificationChanged: (v) =>
                  setState(() => _verification = v ?? 'none'),
              onNotificationsChanged: (v) =>
                  setState(() => _notifications = v ?? 'all'),
              onNsfwChanged: (v) => setState(() => _nsfw = v ?? 'default'),
              onContentFilterChanged: (v) =>
                  setState(() => _contentFilter = v ?? 'disabled'),
              onPublicChanged: (v) => setState(() => _public = v),
              onGuestAccessChanged: (v) => setState(() => _guestAccess = v),
            ),
            const Divider(height: 24),
            _ChannelsSection(
              textChannels: textChannels,
              rulesValue: rulesValue,
              systemValue: systemValue,
              busy: _busy,
              onRulesChanged: (v) => setState(() => _rulesChannelId = v),
              onSystemChanged: (v) => setState(() => _systemChannelId = v),
            ),
            _SaveSettingsButton(busy: _busy, onSave: _saveSettings),
          ],
        ],
        actions: [
          _MembershipSection(onEditNickname: _editOwnNickname),
          if (canManageRoles ||
              canViewAuditLog ||
              canModerate ||
              canManageEmojis ||
              canUseSoundboard) ...[
            const Divider(height: 24),
            _ManagementSection(
              spaceId: widget.spaceId,
              canManageRoles: canManageRoles,
              canViewAuditLog: canViewAuditLog,
              canModerate: canModerate,
              canManageEmojis: canManageEmojis,
              canUseSoundboard: canUseSoundboard,
              canManageSoundboard: canManageSoundboard,
            ),
          ],
          if (isOwner) ...[
            const Divider(height: 24),
            _DangerZoneSection(
              spaceId: widget.spaceId,
              busy: _busy,
              onDeleteSpace: () => _deleteSpace(space.name),
            ),
          ],
        ],
        error: _error == null
            ? null
            : Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: InlineError(_error!, centered: false),
              ),
      ),
    );
  }
}
