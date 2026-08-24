import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/confirm_dialog.dart';
import 'package:bonfire/features/channels/utils/channel_reorder.dart';
import 'package:bonfire/shared/utils/responsive_dialog.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the channel reorder dialog for [spaceId]. Gated on `manage_channels`
/// at the call site. Lets the user drag categories and their children to
/// reorder, persisting each moved channel's `position` (and `parent_id`,
/// when it crossed a category boundary) via `channels.update`. Mirrors the
/// reference client's reorder UI.
Future<void> showAccordChannelReorder(
  BuildContext context, {
  required String spaceId,
  required List<AccordChannel> channels,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ChannelReorder(spaceId: spaceId, channels: channels),
  );
}

class _ChannelReorder extends ConsumerStatefulWidget {
  const _ChannelReorder({required this.spaceId, required this.channels});

  final String spaceId;
  final List<AccordChannel> channels;

  @override
  ConsumerState<_ChannelReorder> createState() => _ChannelReorderState();
}

class _ChannelReorderState extends ConsumerState<_ChannelReorder> {
  /// A flat ordering of [ChannelReorderEntry]s for the ReorderableListView.
  /// Categories carry a parentId of null; channels carry the parent's id (or
  /// null when uncategorized). Drag-reorder swaps the entry in the list; on
  /// save we PATCH any entry whose (parent, position) changed.
  late List<ChannelReorderEntry> _items;
  bool _busy = false;
  String? _error;
  bool _selecting = false;
  final Set<String> _selected = {};

  AccordClient? get _client => ref.accordClient;

  @override
  void initState() {
    super.initState();
    _items = flattenChannelsForReorder(
      widget.channels,
      uncategorizedFirst: false,
    );
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      final entry = _items.removeAt(oldIndex);
      _items.insert(newIndex, entry);
      _recomputeParents();
    });
  }

  /// Re-derives each non-category entry's `parentId` from the category that
  /// most recently appeared above it in the list. An item appearing before any
  /// category lands as uncategorized.
  void _recomputeParents() {
    String? currentParent;
    for (final entry in _items) {
      if (entry.isCategory) {
        currentParent = entry.channel.id;
      } else {
        entry.parentId = currentParent;
      }
    }
  }

  Future<void> _save() async {
    final client = _client;
    if (client == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    // PATCH any channel whose (parent, position) differs from the original.
    final updated = <AccordChannel>[];
    final updates = diffChannelPositions(_items);

    for (final u in updates) {
      final result = await client.channels.update(u.channelId, u.toBody());
      if (!result.ok) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = result.errorOr('Failed to reorder');
        });
        return;
      }
      final data = result.data;
      if (data is AccordChannel) updated.add(data);
    }

    // Mirror successful updates into the channel cache. The gateway echo will
    // typically arrive too, but updating optimistically keeps the UI snappy.
    final notifier = ref.read(
      accordChannelsControllerProvider(widget.spaceId).notifier,
    );
    for (final channel in updated) {
      notifier.upsertChannel(channel);
    }
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _bulkDelete() async {
    final client = _client;
    if (client == null || _selected.isEmpty) return;
    final ids = _selected.toList();
    final ok = await showConfirmDialog(
      context,
      title: 'Delete channels',
      message: 'Delete ${ids.length} channel(s)? This cannot be undone.',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final notifier = ref.read(
      accordChannelsControllerProvider(widget.spaceId).notifier,
    );
    final failed = <String>[];
    for (final id in ids) {
      final result = await client.channels.delete(id);
      if (result.ok) {
        notifier.removeChannel(id);
        _items.removeWhere((e) => e.channel.id == id);
      } else {
        failed.add(id);
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _selected
        ..clear()
        ..addAll(failed);
      _selecting = _selected.isNotEmpty;
      _error = failed.isEmpty ? null : 'Failed to delete ${failed.length}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: dialogConstraints(context, maxWidth: 460, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    _selecting ? Icons.checklist : Icons.reorder,
                    size: 18,
                    color: colors.dirtyWhite,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _selecting ? 'Delete channels' : 'Reorder channels',
                    style: theme.textTheme.titleMedium,
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: _selecting ? 'Done selecting' : 'Select to delete',
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _selecting = !_selecting;
                            if (!_selecting) _selected.clear();
                          }),
                    icon: Icon(
                      _selecting ? Icons.check : Icons.delete_outline,
                      size: 18,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _selecting
                    ? 'Select channels to delete. This cannot be undone.'
                    : 'Drag categories and channels into your preferred order. '
                          'Drop a channel onto a category to move it into that '
                          'category.',
                style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                InlineError(_error!, centered: false),
              ],
              const SizedBox(height: 8),
              Flexible(
                child: _selecting
                    ? ListView.builder(
                        shrinkWrap: true,
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final entry = _items[index];
                          final selected = _selected.contains(entry.channel.id);
                          return CheckboxListTile(
                            value: selected,
                            onChanged: _busy
                                ? null
                                : (v) => setState(() {
                                    if (v == true) {
                                      _selected.add(entry.channel.id);
                                    } else {
                                      _selected.remove(entry.channel.id);
                                    }
                                  }),
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.only(
                              left: entry.isCategory ? 4 : 24,
                              right: 12,
                            ),
                            secondary: Icon(
                              entry.isCategory
                                  ? Icons.folder_outlined
                                  : (entry.channel.type == 'voice'
                                        ? Icons.volume_up
                                        : (entry.channel.type == 'forum'
                                              ? Icons.forum
                                              : Icons.tag)),
                              size: 16,
                              color: colors.dirtyWhite,
                            ),
                            title: Text(
                              entry.channel.name ?? '(unnamed)',
                              style: entry.isCategory
                                  ? theme.textTheme.labelSmall!.copyWith(
                                      color: colors.gray,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    )
                                  : theme.textTheme.bodyMedium,
                            ),
                          );
                        },
                      )
                    : ReorderableListView.builder(
                        shrinkWrap: true,
                        itemCount: _items.length,
                        onReorderItem: _onReorder,
                        itemBuilder: (context, index) {
                          final entry = _items[index];
                          return ListTile(
                            key: ValueKey(entry.channel.id),
                            contentPadding: EdgeInsets.only(
                              left: entry.isCategory ? 4 : 24,
                              right: 12,
                            ),
                            leading: Icon(
                              entry.isCategory
                                  ? Icons.folder_outlined
                                  : (entry.channel.type == 'voice'
                                        ? Icons.volume_up
                                        : (entry.channel.type == 'forum'
                                              ? Icons.forum
                                              : Icons.tag)),
                              size: 16,
                              color: colors.dirtyWhite,
                            ),
                            title: Text(
                              entry.channel.name ?? '(unnamed)',
                              style: entry.isCategory
                                  ? theme.textTheme.labelSmall!.copyWith(
                                      color: colors.gray,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    )
                                  : theme.textTheme.bodyMedium,
                            ),
                            trailing: const Icon(Icons.drag_handle, size: 18),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).maybePop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  if (_selecting)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.error,
                      ),
                      onPressed: _busy || _selected.isEmpty
                          ? null
                          : _bulkDelete,
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.delete_outline, size: 16),
                      label: Text('Delete selected (${_selected.length})'),
                    )
                  else
                    FilledButton(
                      onPressed: _busy ? null : _save,
                      child: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
