import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
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
  /// A flat ordering of `_Entry`s for the ReorderableListView. Categories carry
  /// a parentId of null; channels carry the parent's id (or null when
  /// uncategorized). Drag-reorder swaps the `_Entry` in the list; on save we
  /// walk the list and PATCH any entry whose (parent, position) changed.
  late List<_Entry> _items;
  bool _busy = false;
  String? _error;

  AccordClient? get _client => ref.read(
        accordAuthProvider
            .select((s) => s is AccordAuthLoggedIn ? s.client : null),
      );

  @override
  void initState() {
    super.initState();
    _items = _flatten(widget.channels);
  }

  /// Builds the flat list shown in the reorderable view: each category
  /// followed by its children, then uncategorized channels at the end (in a
  /// synthetic "Uncategorized" group). Order within each group follows the
  /// channel's current `position`.
  /// AccordChannel.position is loosely-typed (`Object?`) so any sort/compare
  /// goes through this helper. Treats missing/non-numeric values as 0 — the
  /// reference client does the same.
  static int _pos(AccordChannel c) {
    final raw = c.position;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw) ?? 0;
    return 0;
  }

  static List<_Entry> _flatten(List<AccordChannel> channels) {
    final sorted = [...channels]..sort((a, b) => _pos(a).compareTo(_pos(b)));
    final categories = sorted.where((c) => c.type == 'category').toList();
    final leaves = sorted.where((c) => c.type != 'category').toList();
    final byParent = <String?, List<AccordChannel>>{};
    for (final c in leaves) {
      byParent.putIfAbsent(c.parentId, () => []).add(c);
    }
    final out = <_Entry>[];
    for (final category in categories) {
      out.add(_Entry.category(category));
      for (final child in byParent[category.id] ?? const <AccordChannel>[]) {
        out.add(_Entry.channel(child, parentId: category.id));
      }
    }
    for (final channel in byParent[null] ?? const <AccordChannel>[]) {
      out.add(_Entry.channel(channel, parentId: null));
    }
    return out;
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
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
    // Walk the new ordering and PATCH any channel whose (parent, position)
    // differs from the original. Position counts within each category bucket
    // so siblings stay coherent (categories share a top-level bucket).
    final updated = <AccordChannel>[];
    final updates = <_Update>[];
    int categoryPos = 0;
    final childPos = <String?, int>{};
    for (final entry in _items) {
      final channel = entry.channel;
      if (entry.isCategory) {
        if (_pos(channel) != categoryPos) {
          updates.add(_Update(channel.id, position: categoryPos));
        }
        categoryPos++;
      } else {
        final pos = childPos[entry.parentId] ?? 0;
        childPos[entry.parentId] = pos + 1;
        final parentChanged = channel.parentId != entry.parentId;
        final positionChanged = _pos(channel) != pos;
        if (parentChanged || positionChanged) {
          updates.add(_Update(channel.id,
              position: pos,
              parentId: parentChanged ? entry.parentId : null,
              includeParent: parentChanged));
        }
      }
    }

    for (final u in updates) {
      final body = <String, dynamic>{'position': u.position};
      if (u.includeParent) body['parent_id'] = u.parentId;
      final result = await client.channels.update(u.channelId, body);
      if (!result.ok) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = result.error?.toString() ?? 'Failed to reorder';
        });
        return;
      }
      final data = result.data;
      if (data is AccordChannel) updated.add(data);
    }

    // Mirror successful updates into the channel cache. The gateway echo will
    // typically arrive too, but updating optimistically keeps the UI snappy.
    final notifier =
        ref.read(accordChannelsControllerProvider(widget.spaceId).notifier);
    for (final channel in updated) {
      notifier.upsertChannel(channel);
    }
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.reorder, size: 18, color: colors.dirtyWhite),
                  const SizedBox(width: 8),
                  Text('Reorder channels',
                      style: theme.textTheme.titleMedium),
                  const Spacer(),
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
                'Drag categories and channels into your preferred order. '
                'Drop a channel onto a category to move it into that category.',
                style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: theme.textTheme.bodySmall!
                        .copyWith(color: colors.red)),
              ],
              const SizedBox(height: 8),
              Flexible(
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  itemCount: _items.length,
                  onReorder: _onReorder,
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

class _Entry {
  _Entry.category(this.channel)
      : isCategory = true,
        parentId = null;
  _Entry.channel(this.channel, {required this.parentId}) : isCategory = false;

  final AccordChannel channel;
  final bool isCategory;
  String? parentId;
}

class _Update {
  const _Update(
    this.channelId, {
    required this.position,
    this.parentId,
    this.includeParent = false,
  });

  final String channelId;
  final int position;
  final String? parentId;
  final bool includeParent;
}
