part of 'accord_home.dart';

/// Sidebar channel list with inline long-press drag-to-reorder for space managers.
class _ChannelDragList extends ConsumerStatefulWidget {
  const _ChannelDragList({
    required this.spaceId,
    required this.channels,
    required this.selectedChannelId,
    required this.onSelect,
    required this.collapsed,
    required this.onToggleCollapsed,
  });

  final String spaceId;
  final List<AccordChannel> channels;
  final String? selectedChannelId;
  final ValueChanged<String> onSelect;
  final Set<String> collapsed;
  final ValueChanged<String> onToggleCollapsed;

  @override
  ConsumerState<_ChannelDragList> createState() => _ChannelDragListState();
}

class _ChannelDragListState extends ConsumerState<_ChannelDragList> {
  late List<ChannelReorderEntry> _items;
  late String _signature;
  bool _persisting = false;
  bool _pendingPersist = false;

  @override
  void initState() {
    super.initState();
    _items = _flatten(widget.channels);
    _signature = _signatureOf(widget.channels);
  }

  @override
  void didUpdateWidget(covariant _ChannelDragList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Ignore incoming list churn while our own optimistic PATCHes are landing;
    // we reconcile once at the end of [_persist].
    if (_persisting) return;
    final sig = _signatureOf(widget.channels);
    if (sig != _signature) _resync();
  }

  void _resync() {
    setState(() {
      _items = _flatten(widget.channels);
      _signature = _signatureOf(widget.channels);
    });
  }

  static String _signatureOf(List<AccordChannel> channels) =>
      channelListSignature(channels);

  /// Uncategorized channels, then categories each followed by their children
  /// (see [flattenChannelsForReorder]).
  static List<ChannelReorderEntry> _flatten(List<AccordChannel> channels) =>
      flattenChannelsForReorder(channels, uncategorizedFirst: true);

  /// The items actually shown: every category, plus the children of categories
  /// that aren't collapsed (uncategorized channels are always shown).
  List<ChannelReorderEntry> get _visible => _items
      .where((e) => e.isCategory || !widget.collapsed.contains(e.parentId))
      .toList();

  void _recomputeParents(ChannelReorderEntry moved) {
    if (moved.isCategory) return;
    String? newParent;
    for (final e in _items) {
      if (e.isCategory) {
        newParent = e.channel.id;
      } else if (identical(e, moved)) {
        moved.parentId = newParent;
        return;
      }
    }
    moved.parentId = null;
  }

  void _onReorder(int oldIndex, int newIndex) {
    final visible = _visible;
    final moved = visible[oldIndex];
    final newVisible = [...visible]..removeAt(oldIndex);
    final ChannelReorderEntry? before = newIndex < newVisible.length
        ? newVisible[newIndex]
        : null;

    // A dragged category carries its contiguous children with it.
    final List<ChannelReorderEntry> block;
    if (moved.isCategory) {
      final start = _items.indexOf(moved);
      var end = start + 1;
      while (end < _items.length && !_items[end].isCategory) {
        end++;
      }
      block = _items.sublist(start, end);
    } else {
      block = [moved];
    }

    setState(() {
      _items.removeWhere(block.contains);
      final insertAt = before == null ? _items.length : _items.indexOf(before);
      _items.insertAll(insertAt < 0 ? _items.length : insertAt, block);
      _recomputeParents(moved);
    });
    _schedulePersist();
  }

  void _schedulePersist() {
    if (_persisting) {
      _pendingPersist = true;
    } else {
      _persist();
    }
  }

  /// Walks the new ordering and PATCHes any channel whose (parent, position)
  /// changed. Positions count within each bucket (categories share one bucket;
  /// each category's children share another) so siblings stay coherent.
  Future<void> _persist() async {
    final client = ref.read(
      accordAuthProvider.select(
        (s) => s is AccordAuthLoggedIn ? s.client : null,
      ),
    );
    if (client == null) return;
    final notifier = ref.read(
      accordChannelsControllerProvider(ref.readActiveServerKey() ?? '', widget.spaceId).notifier,
    );

    final updates = diffChannelPositions(_items);

    if (updates.isEmpty) return;

    _persisting = true;
    try {
      for (final u in updates) {
        await notifier.updateChannel(client, u.channelId, u.toBody());
      }
    } finally {
      _persisting = false;
      if (_pendingPersist && mounted) {
        _pendingPersist = false;
        _persist();
      } else if (mounted) {
        _resync();
      }
    }
  }

  Widget _buildItem(BuildContext context, ChannelReorderEntry entry) {
    if (entry.isCategory) {
      final cat = entry.channel;
      return _categoryHeader(
        context,
        cat,
        spaceId: widget.spaceId,
        canManageChannels: true,
        collapsed: widget.collapsed.contains(cat.id),
        onToggle: () => widget.onToggleCollapsed(cat.id),
      );
    }
    final ch = entry.channel;
    return _channelTile(
      context,
      ch,
      spaceId: widget.spaceId,
      selected: ch.id == widget.selectedChannelId,
      canManageChannels: true,
      onTap: () => widget.onSelect(ch.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      buildDefaultDragHandles: false,
      itemCount: visible.length,
      onReorderItem: _onReorder,
      itemBuilder: (context, index) {
        final entry = visible[index];
        return ReorderableDelayedDragStartListener(
          key: ValueKey(entry.channel.id),
          index: index,
          child: _buildItem(context, entry),
        );
      },
    );
  }
}
