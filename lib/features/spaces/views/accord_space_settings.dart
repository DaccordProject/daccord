import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/permissions.dart';
import 'package:bonfire/features/spaces/controllers/role_preview.dart';
import 'package:bonfire/features/spaces/controllers/space.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
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

/// Resolves a space's `banner` reference to an absolute CDN URL, or null when
/// unset. The field is either a bare asset hash or a server-relative/absolute
/// path; both are handled (mirrors [accordMemberAvatarUrl]).
String? accordSpaceBannerUrl(AccordSpace space, String? cdnUrl) {
  final banner = space.banner;
  if (banner is! String || banner.isEmpty) return null;
  final cdn = cdnUrl ?? '';
  if (banner.contains('/') || banner.startsWith('http')) {
    return AccordCDN.resolvePath(banner, cdnUrl: cdn);
  }
  return AccordCDN.spaceBanner(
    space.id,
    banner,
    format: AccordCDN.autoFormat(banner),
    cdnUrl: cdn,
  );
}

/// Resolves a space's `icon` reference to an absolute CDN URL, or null when
/// unset. Mirrors [accordSpaceBannerUrl].
String? accordSpaceIconUrl(AccordSpace space, String? cdnUrl) {
  final icon = space.icon;
  if (icon is! String || icon.isEmpty) return null;
  final cdn = cdnUrl ?? '';
  if (icon.contains('/') || icon.startsWith('http')) {
    return AccordCDN.resolvePath(icon, cdnUrl: cdn);
  }
  return AccordCDN.spaceIcon(
    space.id,
    icon,
    format: AccordCDN.autoFormat(icon),
    cdnUrl: cdn,
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

  AccordClient? get _client => ref.read(
    accordAuthProvider.select((s) => s is AccordAuthLoggedIn ? s.client : null),
  );

  Set<String> _perms() {
    final space = ref
        .read(spacesControllerProvider)
        ?.firstWhereOrNull((s) => s.id == widget.spaceId);
    final currentUserId = ref.read(
      accordAuthProvider.select(
        (s) => s is AccordAuthLoggedIn ? s.session.userId : null,
      ),
    );
    final isAdmin = ref.read(
      accordAuthProvider.select(
        (s) => s is AccordAuthLoggedIn ? s.session.isAdmin : false,
      ),
    );
    final members = ref.read(accordMembersControllerProvider(widget.spaceId));
    final preview = ref.read(rolePreviewControllerProvider);
    return accordEffectivePermissions(
      space: space,
      selfMember: currentUserId == null ? null : members?[currentUserId],
      roles: space?.roles ?? const <AccordRole>[],
      currentUserId: currentUserId ?? '',
      currentUserIsAdmin: isAdmin,
      previewRoleId: preview?.spaceId == widget.spaceId
          ? preview?.roleId
          : null,
    );
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
      if (!result.ok) _error = result.error?.toString() ?? failure;
    });
    final space = result.data;
    if (result.ok && space is AccordSpace) {
      ref.read(spacesControllerProvider.notifier).upsertSpace(space);
      ref.read(spaceControllerProvider(space.id).notifier).setSpace(space);
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
        _error = result.error?.toString() ?? 'Failed to delete space';
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
    final currentUserId = ref.read(
      accordAuthProvider.select(
        (s) => s is AccordAuthLoggedIn ? s.session.userId : null,
      ),
    );
    if (client == null || currentUserId == null) return;
    final members = ref.read(accordMembersControllerProvider(widget.spaceId));
    final me = members?[currentUserId];
    final initial = me?.nickname ?? '';
    final controller = TextEditingController(text: initial);
    final next = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change nickname'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nickname',
            hintText: 'Leave empty to reset to your display name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          if (initial.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(''),
              child: const Text('Reset'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
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
      setState(
        () => _error = result.error?.toString() ?? 'Failed to update nickname',
      );
      return;
    }
    final updated = result.data;
    if (updated is AccordMember) {
      ref
          .read(accordMembersControllerProvider(widget.spaceId).notifier)
          .upsertMember(updated);
    }
  }

  Widget _dropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      items: items,
      onChanged: _busy ? null : onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final space = ref.watch(
      spacesControllerProvider.select(
        (s) => s?.firstWhereOrNull((sp) => sp.id == widget.spaceId),
      ),
    );
    final cdnUrl = ref.watch(
      accordAuthProvider.select(
        (s) => s is AccordAuthLoggedIn ? s.session.server.cdnUrl : null,
      ),
    );
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
    final currentUserId = ref.watch(
      accordAuthProvider.select(
        (s) => s is AccordAuthLoggedIn ? s.session.userId : null,
      ),
    );
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
        (ref.watch(accordChannelsControllerProvider(widget.spaceId)) ??
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
          _SectionHeader('Banner'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    height: 130,
                    width: double.infinity,
                    color: colors.darkGray,
                    child: bannerUrl == null
                        ? Center(
                            child: Icon(
                              Icons.image_outlined,
                              color: colors.gray,
                              size: 32,
                            ),
                          )
                        : CachedNetworkImage(
                            imageUrl: bannerUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) => Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: colors.gray,
                              ),
                            ),
                          ),
                  ),
                ),
                if (canManageSpace) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: _busy ? null : _pickBanner,
                        icon: const Icon(Icons.upload, size: 18),
                        label: Text(bannerUrl == null ? 'Upload' : 'Change'),
                      ),
                      const SizedBox(width: 8),
                      if (bannerUrl != null)
                        TextButton(
                          onPressed: _busy ? null : _removeBanner,
                          style: TextButton.styleFrom(
                            foregroundColor: colors.red,
                          ),
                          child: const Text('Remove'),
                        ),
                    ],
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'You need Manage Space to edit the banner.',
                      style: theme.textTheme.bodySmall!.copyWith(
                        color: colors.gray,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (canManageSpace) ...[
            const Divider(height: 24),
            _SectionHeader('Overview'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: colors.darkGray,
                        backgroundImage: _pendingIconDataUri != null
                            ? null
                            : (_iconRemoved || iconUrl == null
                                  ? null
                                  : CachedNetworkImageProvider(iconUrl)),
                        child:
                            (_pendingIconDataUri != null ||
                                (!_iconRemoved && iconUrl != null))
                            ? null
                            : Icon(Icons.image_outlined, color: colors.gray),
                      ),
                      const SizedBox(height: 4),
                      TextButton(
                        onPressed: _busy ? null : _pickIcon,
                        child: Text(iconUrl == null ? 'Upload' : 'Change'),
                      ),
                      if (iconUrl != null || _pendingIconDataUri != null)
                        TextButton(
                          onPressed: _busy ? null : _markIconRemoved,
                          style: TextButton.styleFrom(
                            foregroundColor: colors.red,
                          ),
                          child: const Text('Remove'),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _name,
                          enabled: !_busy,
                          decoration: const InputDecoration(
                            labelText: 'Name',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _description,
                          enabled: !_busy,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Description',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 24),
            _SectionHeader('Moderation'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Column(
                children: [
                  _dropdown<String>(
                    label: 'Verification level',
                    value: _verification,
                    items: [
                      for (final v in _verificationLevels)
                        DropdownMenuItem(value: v.value, child: Text(v.label)),
                    ],
                    onChanged: (v) =>
                        setState(() => _verification = v ?? 'none'),
                  ),
                  const SizedBox(height: 8),
                  _dropdown<String>(
                    label: 'Default notifications',
                    value: _notifications,
                    items: [
                      for (final v in _notificationLevels)
                        DropdownMenuItem(value: v.value, child: Text(v.label)),
                    ],
                    onChanged: (v) =>
                        setState(() => _notifications = v ?? 'all'),
                  ),
                  const SizedBox(height: 8),
                  _dropdown<String>(
                    label: 'NSFW level',
                    value: _nsfw,
                    items: [
                      for (final v in _nsfwLevels)
                        DropdownMenuItem(value: v.value, child: Text(v.label)),
                    ],
                    onChanged: (v) => setState(() => _nsfw = v ?? 'default'),
                  ),
                  const SizedBox(height: 8),
                  _dropdown<String>(
                    label: 'Explicit content filter',
                    value: _contentFilter,
                    items: [
                      for (final v in _contentFilters)
                        DropdownMenuItem(value: v.value, child: Text(v.label)),
                    ],
                    onChanged: (v) =>
                        setState(() => _contentFilter = v ?? 'disabled'),
                  ),
                ],
              ),
            ),
            SwitchListTile(
              value: _public,
              onChanged: _busy ? null : (v) => setState(() => _public = v),
              title: const Text('Public space'),
              subtitle: const Text('Discoverable and joinable by anyone'),
            ),
            SwitchListTile(
              value: _guestAccess,
              onChanged: _busy ? null : (v) => setState(() => _guestAccess = v),
              title: const Text('Allow guest access'),
              subtitle: const Text('Let unauthenticated users browse'),
            ),
            const Divider(height: 24),
            _SectionHeader('Channels'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Column(
                children: [
                  _dropdown<String?>(
                    label: 'Rules channel',
                    value: rulesValue,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('None')),
                      for (final c in textChannels)
                        DropdownMenuItem(
                          value: c.id,
                          child: Text('# ${c.name ?? c.id}'),
                        ),
                    ],
                    onChanged: (v) => setState(() => _rulesChannelId = v),
                  ),
                  const SizedBox(height: 8),
                  _dropdown<String?>(
                    label: 'System messages channel',
                    value: systemValue,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('None')),
                      for (final c in textChannels)
                        DropdownMenuItem(
                          value: c.id,
                          child: Text('# ${c.name ?? c.id}'),
                        ),
                    ],
                    onChanged: (v) => setState(() => _systemChannelId = v),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _saveSettings,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save, size: 18),
                  label: const Text('Save settings'),
                ),
              ),
            ),
          ],
        ],
        actions: [
          _SectionHeader('Membership'),
          ListTile(
            leading: Icon(Icons.badge_outlined, color: colors.dirtyWhite),
            title: const Text('Change your nickname'),
            subtitle: const Text('How you appear in this space'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editOwnNickname(),
          ),
          if (canManageRoles ||
              canViewAuditLog ||
              canModerate ||
              canManageEmojis ||
              canUseSoundboard) ...[
            const Divider(height: 24),
            _SectionHeader('Management'),
            if (canManageRoles)
              ListTile(
                leading: Icon(Icons.shield_outlined, color: colors.dirtyWhite),
                title: const Text('Roles'),
                subtitle: const Text('Create, edit, and order roles'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    showAccordRoleManagement(context, spaceId: widget.spaceId),
              ),
            if (canViewAuditLog)
              ListTile(
                leading: Icon(Icons.history, color: colors.dirtyWhite),
                title: const Text('Audit log'),
                subtitle: const Text('Recent moderation and admin actions'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    showAccordAuditLog(context, spaceId: widget.spaceId),
              ),
            if (canModerate) ...[
              ListTile(
                leading: Icon(Icons.gavel, color: colors.dirtyWhite),
                title: const Text('Banned members'),
                subtitle: const Text('Review and unban members'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    showAccordBanList(context, spaceId: widget.spaceId),
              ),
              ListTile(
                leading: Icon(Icons.flag_outlined, color: colors.dirtyWhite),
                title: const Text('Reports'),
                subtitle: const Text('Review and resolve member reports'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showReportsPanel(context, spaceId: widget.spaceId),
              ),
            ],
            if (canManageEmojis)
              ListTile(
                leading: Icon(
                  Icons.emoji_emotions_outlined,
                  color: colors.dirtyWhite,
                ),
                title: const Text('Custom emoji'),
                subtitle: const Text('Upload, rename, and delete emoji'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    showAccordEmojiManagement(context, spaceId: widget.spaceId),
              ),
            if (canUseSoundboard)
              ListTile(
                leading: Icon(Icons.graphic_eq, color: colors.dirtyWhite),
                title: const Text('Soundboard'),
                subtitle: const Text('Play and manage soundboard clips'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showAccordSoundboard(
                  context,
                  spaceId: widget.spaceId,
                  canManage: canManageSoundboard,
                ),
              ),
          ],
          if (isOwner) ...[
            const Divider(height: 24),
            _SectionHeader('Danger zone'),
            ListTile(
              leading: Icon(Icons.swap_horiz, color: colors.dirtyWhite),
              title: const Text('Transfer ownership'),
              subtitle: const Text('Hand this space to another member'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  showTransferOwnership(context, spaceId: widget.spaceId),
            ),
            ListTile(
              leading: Icon(Icons.delete_forever, color: colors.red),
              title: Text('Delete space', style: TextStyle(color: colors.red)),
              subtitle: const Text('Permanently remove this space'),
              onTap: _busy ? null : () => _deleteSpace(space.name),
            ),
          ],
        ],
        error: _error == null
            ? null
            : Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  _error!,
                  style: theme.textTheme.bodySmall!.copyWith(color: colors.red),
                ),
              ),
      ),
    );
  }
}

/// Lays out the space-settings sections in one scrolling page. On wide
/// (desktop) viewports the editable [form] and the [actions] tiles sit in two
/// side-by-side columns constrained to a readable max width; on narrow
/// viewports they stack into a single column (the mobile layout).
class _AdaptiveSettingsBody extends StatelessWidget {
  const _AdaptiveSettingsBody({
    required this.form,
    required this.actions,
    this.error,
  });

  final List<Widget> form;
  final List<Widget> actions;
  final Widget? error;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Below this the two columns would be too cramped, so stack them.
        final twoColumn = constraints.maxWidth >= 880;
        if (!twoColumn) {
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              ...form,
              const Divider(height: 24),
              ...actions,
              if (error != null) error!,
            ],
          );
        }
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: form,
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: actions,
                        ),
                      ),
                    ],
                  ),
                  if (error != null) error!,
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium!.copyWith(
          color: colors.gray,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
