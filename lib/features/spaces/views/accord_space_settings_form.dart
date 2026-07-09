part of 'accord_space_settings.dart';

/// Shared outlined dropdown used by the moderation/channel pickers below.
/// Renders exactly the dropdown the old `_dropdown` state helper produced.
class _SettingsDropdown<T> extends StatelessWidget {
  const _SettingsDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final bool enabled;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      items: items,
      onChanged: enabled ? onChanged : null,
    );
  }
}

/// "Banner" section: the 16:9 banner preview plus upload/change/remove
/// controls (or a hint when the user lacks Manage Space).
class _BannerSection extends StatelessWidget {
  const _BannerSection({
    required this.bannerUrl,
    required this.canManage,
    required this.busy,
    required this.onPick,
    required this.onRemove,
  });

  final String? bannerUrl;
  final bool canManage;
  final bool busy;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final bannerUrl = this.bannerUrl;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('Banner'),
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
              if (canManage) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: busy ? null : onPick,
                      icon: const Icon(Icons.upload, size: 18),
                      label: Text(bannerUrl == null ? 'Upload' : 'Change'),
                    ),
                    const SizedBox(width: 8),
                    if (bannerUrl != null)
                      TextButton(
                        onPressed: busy ? null : onRemove,
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
      ],
    );
  }
}

/// "Overview" section: icon avatar with upload/remove controls plus the name
/// and description fields. The [TextEditingController]s stay owned by the
/// settings screen's state.
class _OverviewSection extends StatelessWidget {
  const _OverviewSection({
    required this.nameController,
    required this.descriptionController,
    required this.iconUrl,
    required this.pendingIconDataUri,
    required this.iconRemoved,
    required this.busy,
    required this.onPickIcon,
    required this.onRemoveIcon,
  });

  final TextEditingController nameController;
  final TextEditingController descriptionController;
  final String? iconUrl;
  final String? pendingIconDataUri;
  final bool iconRemoved;
  final bool busy;
  final VoidCallback onPickIcon;
  final VoidCallback onRemoveIcon;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final iconUrl = this.iconUrl;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('Overview'),
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
                    backgroundImage: pendingIconDataUri != null
                        ? null
                        : (iconRemoved || iconUrl == null
                              ? null
                              : CachedNetworkImageProvider(iconUrl)),
                    child:
                        (pendingIconDataUri != null ||
                            (!iconRemoved && iconUrl != null))
                        ? null
                        : Icon(Icons.image_outlined, color: colors.gray),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: busy ? null : onPickIcon,
                    child: Text(iconUrl == null ? 'Upload' : 'Change'),
                  ),
                  if (iconUrl != null || pendingIconDataUri != null)
                    TextButton(
                      onPressed: busy ? null : onRemoveIcon,
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
                      controller: nameController,
                      enabled: !busy,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descriptionController,
                      enabled: !busy,
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
      ],
    );
  }
}

/// "Moderation" section: verification/notification/NSFW/content-filter
/// dropdowns plus the public and guest-access switches.
class _ModerationSection extends StatelessWidget {
  const _ModerationSection({
    required this.verification,
    required this.notifications,
    required this.nsfw,
    required this.contentFilter,
    required this.isPublic,
    required this.guestAccess,
    required this.busy,
    required this.onVerificationChanged,
    required this.onNotificationsChanged,
    required this.onNsfwChanged,
    required this.onContentFilterChanged,
    required this.onPublicChanged,
    required this.onGuestAccessChanged,
  });

  final String verification;
  final String notifications;
  final String nsfw;
  final String contentFilter;
  final bool isPublic;
  final bool guestAccess;
  final bool busy;
  final ValueChanged<String?> onVerificationChanged;
  final ValueChanged<String?> onNotificationsChanged;
  final ValueChanged<String?> onNsfwChanged;
  final ValueChanged<String?> onContentFilterChanged;
  final ValueChanged<bool> onPublicChanged;
  final ValueChanged<bool> onGuestAccessChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('Moderation'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Column(
            children: [
              _SettingsDropdown<String>(
                label: 'Verification level',
                value: verification,
                items: [
                  for (final v in _verificationLevels)
                    DropdownMenuItem(value: v.value, child: Text(v.label)),
                ],
                enabled: !busy,
                onChanged: onVerificationChanged,
              ),
              const SizedBox(height: 8),
              _SettingsDropdown<String>(
                label: 'Default notifications',
                value: notifications,
                items: [
                  for (final v in _notificationLevels)
                    DropdownMenuItem(value: v.value, child: Text(v.label)),
                ],
                enabled: !busy,
                onChanged: onNotificationsChanged,
              ),
              const SizedBox(height: 8),
              _SettingsDropdown<String>(
                label: 'NSFW level',
                value: nsfw,
                items: [
                  for (final v in _nsfwLevels)
                    DropdownMenuItem(value: v.value, child: Text(v.label)),
                ],
                enabled: !busy,
                onChanged: onNsfwChanged,
              ),
              const SizedBox(height: 8),
              _SettingsDropdown<String>(
                label: 'Explicit content filter',
                value: contentFilter,
                items: [
                  for (final v in _contentFilters)
                    DropdownMenuItem(value: v.value, child: Text(v.label)),
                ],
                enabled: !busy,
                onChanged: onContentFilterChanged,
              ),
            ],
          ),
        ),
        SwitchListTile(
          value: isPublic,
          onChanged: busy ? null : onPublicChanged,
          title: const Text('Public space'),
          subtitle: const Text('Discoverable and joinable by anyone'),
        ),
        SwitchListTile(
          value: guestAccess,
          onChanged: busy ? null : onGuestAccessChanged,
          title: const Text('Allow guest access'),
          subtitle: const Text('Let unauthenticated users browse'),
        ),
      ],
    );
  }
}

/// "Channels" section: the rules and system-messages channel pickers.
class _ChannelsSection extends StatelessWidget {
  const _ChannelsSection({
    required this.textChannels,
    required this.rulesValue,
    required this.systemValue,
    required this.busy,
    required this.onRulesChanged,
    required this.onSystemChanged,
  });

  final List<AccordChannel> textChannels;
  final String? rulesValue;
  final String? systemValue;
  final bool busy;
  final ValueChanged<String?> onRulesChanged;
  final ValueChanged<String?> onSystemChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('Channels'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Column(
            children: [
              _SettingsDropdown<String?>(
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
                enabled: !busy,
                onChanged: onRulesChanged,
              ),
              const SizedBox(height: 8),
              _SettingsDropdown<String?>(
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
                enabled: !busy,
                onChanged: onSystemChanged,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The right-aligned "Save settings" button that flushes the whole form.
class _SaveSettingsButton extends StatelessWidget {
  const _SaveSettingsButton({required this.busy, required this.onSave});

  final bool busy;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Align(
        alignment: Alignment.centerRight,
        child: FilledButton.icon(
          onPressed: busy ? null : onSave,
          icon: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save, size: 18),
          label: const Text('Save settings'),
        ),
      ),
    );
  }
}
