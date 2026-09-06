import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/utils/confirm_dialog.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/channels/views/channel_permissions.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The channel types a user can create from the UI. Categories group other
/// channels; the rest are leaf channels.
const _channelTypes = <({String value, String label, IconData icon})>[
  (value: 'text', label: 'Text', icon: Icons.tag),
  (value: 'voice', label: 'Voice', icon: Icons.volume_up),
  (value: 'forum', label: 'Forum', icon: Icons.forum),
  (value: 'announcement', label: 'Announcement', icon: Icons.campaign),
  (value: 'category', label: 'Category', icon: Icons.folder),
];

/// Channel types whose stored messages and rendering are identical, so an
/// existing channel may be switched between them retroactively without losing
/// data. Mirrors accordserver's `is_non_destructive_type_change`; the type
/// selector in edit mode is limited to this set.
const _textLikeTypes = <String>{'text', 'announcement'};

/// Slowmode (rate-limit per user) presets in seconds (0 = off). Mirrors the
/// reference client's channel edit dialog.
const _slowmodePresets = <({String label, int seconds})>[
  (label: 'Off', seconds: 0),
  (label: '5s', seconds: 5),
  (label: '10s', seconds: 10),
  (label: '30s', seconds: 30),
  (label: '1m', seconds: 60),
  (label: '5m', seconds: 300),
  (label: '15m', seconds: 900),
  (label: '1h', seconds: 3600),
  (label: '6h', seconds: 21600),
];

/// Opens the "create channel" dialog for [spaceId]. When [parentId] is set the
/// new channel is nested under that category by default.
Future<void> showCreateChannelDialog(
  BuildContext context, {
  required String spaceId,
  String? parentId,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ChannelEditorDialog(spaceId: spaceId, parentId: parentId),
  );
}

/// Opens the "edit channel" dialog for an existing [channel]. Offers rename,
/// topic editing, and deletion.
Future<void> showEditChannelDialog(
  BuildContext context, {
  required String spaceId,
  required AccordChannel channel,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) =>
        _ChannelEditorDialog(spaceId: spaceId, channel: channel),
  );
}

/// Confirms, then deletes [channel] from [spaceId]. Returns true when deleted.
/// Shared by the edit dialog and the channel/category context menus so the
/// confirmation copy and failure handling stay consistent. Shows a SnackBar on
/// failure (the edit dialog surfaces its own inline error and ignores this).
Future<bool> confirmAndDeleteChannel(
  BuildContext context,
  WidgetRef ref, {
  required String spaceId,
  required AccordChannel channel,
}) async {
  final isCategory = channel.type == 'category';
  final noun = isCategory ? 'category' : 'channel';
  final confirmed = await showConfirmDialog(
    context,
    title: 'Delete $noun',
    message: 'Delete "${channel.name ?? channel.id}"? This cannot be undone.',
    confirmLabel: 'Delete',
  );
  if (confirmed != true) return false;
  final client = ref.accordClient;
  if (client == null) return false;
  final ok = await ref
      .read(accordChannelsControllerProvider(ref.readActiveServerKey() ?? '', spaceId).notifier)
      .deleteChannel(client, channel.id);
  if (!ok && context.mounted) {
    showInfoSnack(context, 'Failed to delete $noun');
  }
  return ok;
}

class _ChannelEditorDialog extends ConsumerStatefulWidget {
  const _ChannelEditorDialog({
    required this.spaceId,
    this.channel,
    this.parentId,
  });

  final String spaceId;
  final AccordChannel? channel;
  final String? parentId;

  @override
  ConsumerState<_ChannelEditorDialog> createState() =>
      _ChannelEditorDialogState();
}

class _ChannelEditorDialogState extends ConsumerState<_ChannelEditorDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.channel?.name ?? '');
  late final TextEditingController _topic =
      TextEditingController(text: widget.channel?.topic ?? '');
  late String _type = widget.channel?.type ?? 'text';
  late String? _parentId = widget.channel?.parentId ?? widget.parentId;
  late bool _nsfw = widget.channel?.nsfw ?? false;
  late int _rateLimit = asInt(widget.channel?.rateLimit);
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.channel != null;

  @override
  void dispose() {
    _name.dispose();
    _topic.dispose();
    super.dispose();
  }

  AccordClient? get _client => ref.accordClient;

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    final client = _client;
    if (client == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final controller =
        ref.read(accordChannelsControllerProvider(ref.readActiveServerKey() ?? '', widget.spaceId).notifier);
    final topic = _topic.text.trim();
    final bool ok;
    final supportsModeration = _type != 'category';
    if (_isEdit) {
      final data = <String, dynamic>{
        'name': name,
        'topic': topic.isEmpty ? null : topic,
        if (_textLikeTypes.contains(widget.channel!.type) &&
            _textLikeTypes.contains(_type) &&
            _type != widget.channel!.type)
          'type': _type,
        if (supportsModeration) 'nsfw': _nsfw,
        if (supportsModeration) 'rate_limit': _rateLimit,
      };
      ok = await controller.updateChannel(client, widget.channel!.id, data);
    } else {
      final data = <String, dynamic>{
        'name': name,
        'type': _type,
        if (topic.isNotEmpty) 'topic': topic,
        if (_parentId != null && _type != 'category') 'parent_id': _parentId,
        if (supportsModeration && _nsfw) 'nsfw': true,
        if (supportsModeration && _rateLimit > 0) 'rate_limit': _rateLimit,
      };
      ok = await controller.createChannel(client, data) != null;
    }
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).maybePop();
    } else {
      setState(() {
        _busy = false;
        _error = _isEdit ? 'Failed to save channel' : 'Failed to create channel';
      });
    }
  }

  Future<void> _delete() async {
    final client = _client;
    final channel = widget.channel;
    if (client == null || channel == null) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete channel',
      message: 'Delete "${channel.name ?? channel.id}"? This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final controller =
        ref.read(accordChannelsControllerProvider(ref.readActiveServerKey() ?? '', widget.spaceId).notifier);
    final ok = await controller.deleteChannel(client, channel.id);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).maybePop();
    } else {
      setState(() {
        _busy = false;
        _error = 'Failed to delete channel';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Categories the new channel can be nested under (edit keeps the channel's
    // own category fixed for simplicity).
    final categories = ref
            .watch(accordChannelsControllerProvider(ref.readActiveServerKey() ?? '', widget.spaceId))
            ?.where((c) => c.type == 'category')
            .toList() ??
        const <AccordChannel>[];
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_isEdit ? 'Edit channel' : 'Create channel',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 16),
              _ChannelNameField(
                controller: _name,
                enabled: !_busy,
                onSubmitted: _submit,
              ),
              const SizedBox(height: 12),
              if (!_isEdit)
                _CreateTypeSelector(
                  type: _type,
                  parentId: _parentId,
                  categories: categories,
                  busy: _busy,
                  onTypeChanged: (v) => setState(() => _type = v ?? 'text'),
                  onParentChanged: (v) => setState(() => _parentId = v),
                ),
              // Edit mode: allow switching between non-destructive (text-like)
              // types only. Voice/category/forum channels show no selector since
              // no safe conversion exists.
              if (_isEdit && _textLikeTypes.contains(widget.channel!.type))
                _EditTypeSelector(
                  type: _type,
                  originalType: widget.channel!.type,
                  busy: _busy,
                  onChanged: (v) =>
                      setState(() => _type = v ?? widget.channel!.type),
                ),
              if (_type != 'category')
                _ChannelTopicField(controller: _topic, enabled: !_busy),
              if (_type != 'category')
                _ChannelModerationFields(
                  nsfw: _nsfw,
                  rateLimit: _rateLimit,
                  busy: _busy,
                  onNsfwChanged: (v) => setState(() => _nsfw = v),
                  onRateLimitChanged: (v) =>
                      setState(() => _rateLimit = v ?? 0),
                ),
              if (_isEdit && _type != 'category')
                _PermissionsButtonRow(
                  enabled: !_busy,
                  onShowPermissions: () => showChannelPermissionsDialog(
                    context,
                    spaceId: widget.spaceId,
                    channel: widget.channel!,
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: theme.textTheme.bodySmall!
                        .copyWith(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 20),
              _EditorActionsRow(
                isEdit: _isEdit,
                busy: _busy,
                onDelete: _delete,
                onSubmit: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The channel name text field (autofocused; Enter submits).
class _ChannelNameField extends StatelessWidget {
  const _ChannelNameField({
    required this.controller,
    required this.enabled,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: true,
      enabled: enabled,
      decoration: const InputDecoration(
        labelText: 'Name',
        isDense: true,
        border: OutlineInputBorder(),
      ),
      onSubmitted: (_) => onSubmitted(),
    );
  }
}

/// Create mode: the channel-type dropdown plus (for leaf channels, when
/// categories exist) the parent-category picker, with their trailing spacers.
class _CreateTypeSelector extends StatelessWidget {
  const _CreateTypeSelector({
    required this.type,
    required this.parentId,
    required this.categories,
    required this.busy,
    required this.onTypeChanged,
    required this.onParentChanged,
  });

  final String type;
  final String? parentId;
  final List<AccordChannel> categories;
  final bool busy;
  final ValueChanged<String?> onTypeChanged;
  final ValueChanged<String?> onParentChanged;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: type,
          decoration: const InputDecoration(
            labelText: 'Type',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: [
            for (final t in _channelTypes)
              DropdownMenuItem(
                value: t.value,
                child: Row(
                  children: [
                    Icon(t.icon, size: 16, color: colors.dirtyWhite),
                    const SizedBox(width: 8),
                    Text(t.label),
                  ],
                ),
              ),
          ],
          onChanged: busy ? null : onTypeChanged,
        ),
        const SizedBox(height: 12),
        if (type != 'category' && categories.isNotEmpty)
          DropdownButtonFormField<String?>(
            initialValue: parentId,
            decoration: const InputDecoration(
              labelText: 'Category',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('None')),
              for (final c in categories)
                DropdownMenuItem(value: c.id, child: Text(c.name ?? c.id)),
            ],
            onChanged: busy ? null : onParentChanged,
          ),
        if (type != 'category' && categories.isNotEmpty)
          const SizedBox(height: 12),
      ],
    );
  }
}

/// Edit mode: the type switcher limited to non-destructive (text-like) types,
/// with its trailing spacer.
class _EditTypeSelector extends StatelessWidget {
  const _EditTypeSelector({
    required this.type,
    required this.originalType,
    required this.busy,
    required this.onChanged,
  });

  final String type;
  final String originalType;
  final bool busy;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _textLikeTypes.contains(type) ? type : originalType,
          decoration: const InputDecoration(
            labelText: 'Type',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: [
            for (final t in _channelTypes)
              if (_textLikeTypes.contains(t.value))
                DropdownMenuItem(
                  value: t.value,
                  child: Row(
                    children: [
                      Icon(t.icon, size: 16, color: colors.dirtyWhite),
                      const SizedBox(width: 8),
                      Text(t.label),
                    ],
                  ),
                ),
          ],
          onChanged: busy ? null : onChanged,
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// The optional topic text field (leaf channels only).
class _ChannelTopicField extends StatelessWidget {
  const _ChannelTopicField({required this.controller, required this.enabled});

  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      minLines: 1,
      maxLines: 3,
      decoration: const InputDecoration(
        labelText: 'Topic (optional)',
        isDense: true,
        border: OutlineInputBorder(),
      ),
    );
  }
}

/// Moderation block (leaf channels only): NSFW toggle plus the slowmode
/// preset picker, with the spacers around them.
class _ChannelModerationFields extends StatelessWidget {
  const _ChannelModerationFields({
    required this.nsfw,
    required this.rateLimit,
    required this.busy,
    required this.onNsfwChanged,
    required this.onRateLimitChanged,
  });

  final bool nsfw;
  final int rateLimit;
  final bool busy;
  final ValueChanged<bool> onNsfwChanged;
  final ValueChanged<int?> onRateLimitChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        SwitchListTile(
          value: nsfw,
          onChanged: busy ? null : onNsfwChanged,
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Age-restricted (NSFW)'),
          subtitle: Text('Users must confirm before viewing',
              style: theme.textTheme.bodySmall),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          initialValue: _slowmodePresets.any((p) => p.seconds == rateLimit)
              ? rateLimit
              : 0,
          decoration: const InputDecoration(
            labelText: 'Slowmode',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          items: [
            for (final p in _slowmodePresets)
              DropdownMenuItem(value: p.seconds, child: Text(p.label)),
          ],
          onChanged: busy ? null : onRateLimitChanged,
        ),
      ],
    );
  }
}

/// Edit mode: the row with the button opening the per-channel permission
/// overrides dialog, with its leading spacer.
class _PermissionsButtonRow extends StatelessWidget {
  const _PermissionsButtonRow({
    required this.enabled,
    required this.onShowPermissions,
  });

  final bool enabled;
  final VoidCallback onShowPermissions;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: enabled ? onShowPermissions : null,
            icon: Icon(Icons.lock_outline, size: 18, color: colors.dirtyWhite),
            label: const Text('Permissions'),
          ),
        ),
      ],
    );
  }
}

/// Bottom action row: Delete (edit mode only), Cancel, and Save/Create.
class _EditorActionsRow extends StatelessWidget {
  const _EditorActionsRow({
    required this.isEdit,
    required this.busy,
    required this.onDelete,
    required this.onSubmit,
  });

  final bool isEdit;
  final bool busy;
  final VoidCallback onDelete;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        if (isEdit)
          TextButton.icon(
            onPressed: busy ? null : onDelete,
            icon: Icon(Icons.delete_outline,
                size: 18, color: theme.colorScheme.error),
            label: Text('Delete',
                style: TextStyle(color: theme.colorScheme.error)),
          ),
        const Spacer(),
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).maybePop(),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: busy ? null : onSubmit,
          child: Text(isEdit ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}
