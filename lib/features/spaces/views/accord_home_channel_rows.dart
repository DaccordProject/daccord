part of 'accord_home.dart';

/// A category row for the static list and the drag list alike: the inline
/// "add channel"/edit affordances are wired only for managers of a real space.
_CategoryHeader _categoryHeader(
  BuildContext context,
  AccordChannel category, {
  required String? spaceId,
  required bool canManageChannels,
  required bool collapsed,
  required VoidCallback onToggle,
}) => _CategoryHeader(
  category: category,
  spaceId: spaceId,
  canManageChannels: canManageChannels,
  collapsed: collapsed,
  onToggle: onToggle,
  onAdd: canManageChannels && spaceId != null
      ? () => showCreateChannelDialog(
          context,
          spaceId: spaceId,
          parentId: category.id,
        )
      : null,
  onEdit: canManageChannels && spaceId != null
      ? () =>
            showEditChannelDialog(context, spaceId: spaceId, channel: category)
      : null,
);

/// A channel row for the static list and the drag list alike; see
/// [_categoryHeader] for the edit affordance rule.
_ChannelTile _channelTile(
  BuildContext context,
  AccordChannel channel, {
  required String? spaceId,
  required bool selected,
  required bool canManageChannels,
  required VoidCallback onTap,
}) => _ChannelTile(
  channel: channel,
  spaceId: spaceId,
  selected: selected,
  canManageChannels: canManageChannels,
  onTap: onTap,
  onEdit: canManageChannels && spaceId != null
      ? () => showEditChannelDialog(context, spaceId: spaceId, channel: channel)
      : null,
);

class _CategoryHeader extends ConsumerWidget {
  const _CategoryHeader({
    required this.category,
    required this.spaceId,
    required this.canManageChannels,
    required this.collapsed,
    required this.onToggle,
    this.onAdd,
    this.onEdit,
  });

  final AccordChannel category;
  final String? spaceId;
  final bool canManageChannels;
  final bool collapsed;
  final VoidCallback onToggle;
  final VoidCallback? onAdd;
  final VoidCallback? onEdit;

  void _showMenu(BuildContext context, WidgetRef ref, [Offset? position]) {
    final id = spaceId;
    if (id == null) return;
    showCategoryContextMenu(
      context,
      ref,
      category: category,
      spaceId: id,
      canManageChannels: canManageChannels,
      collapsed: collapsed,
      onToggle: onToggle,
      globalPosition: position,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    return InkWell(
      onTap: onToggle,
      onLongPress: () => _showMenu(context, ref, null),
      onSecondaryTapUp: (d) => _showMenu(context, ref, d.globalPosition),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 2),
        child: Row(
          children: [
            Icon(
              collapsed ? Icons.chevron_right : Icons.expand_more,
              size: 14,
              color: colors.gray,
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Text(
                (category.name ?? '').toUpperCase(),
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  color: colors.gray,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            if (onEdit != null)
              InkWell(
                onTap: onEdit,
                child: Icon(Icons.settings, size: 14, color: colors.gray),
              ),
            if (onAdd != null) ...[
              const SizedBox(width: 6),
              InkWell(
                onTap: onAdd,
                child: Icon(Icons.add, size: 16, color: colors.gray),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChannelTile extends ConsumerStatefulWidget {
  const _ChannelTile({
    required this.channel,
    required this.spaceId,
    required this.selected,
    required this.canManageChannels,
    required this.onTap,
    this.onEdit,
  });

  final AccordChannel channel;
  final String? spaceId;
  final bool selected;
  final bool canManageChannels;
  final VoidCallback onTap;
  final VoidCallback? onEdit;

  @override
  ConsumerState<_ChannelTile> createState() => _ChannelTileState();
}

class _ChannelTileState extends ConsumerState<_ChannelTile> {
  bool _hovered = false;

  /// When this row was last clicked, for the double-click-to-join fast path
  /// (see [isVoiceDoubleTap]). Per-tile, so clicking two rows in quick
  /// succession can't be mistaken for a double-click.
  DateTime? _lastTapAt;

  bool get _isVoice => widget.channel.type == 'voice';

  bool get _connectedHere =>
      ref.read(voiceControllerProvider).channelId == widget.channel.id;

  /// Explicitly connects to this voice channel. Selecting the channel never
  /// does this any more (#202) — only the row's hover button, its double-click,
  /// its context menu, and the lobby's Join button do.
  void _joinVoice() {
    final spaceId = widget.spaceId;
    if (!_isVoice || spaceId == null || _connectedHere) return;
    ref.read(voiceControllerProvider.notifier).join(widget.channel.id, spaceId);
  }

  /// Selects the channel; a second click inside the double-click window joins it
  /// instead of re-selecting (the first click already opened the tab).
  void _handleTap() {
    final now = DateTime.now();
    if (_isVoice && isVoiceDoubleTap(_lastTapAt, now)) {
      _lastTapAt = null;
      _joinVoice();
      return;
    }
    _lastTapAt = now;
    widget.onTap();
  }

  void _showMenu([Offset? position]) {
    final spaceId = widget.spaceId;
    if (spaceId == null) return;
    final connected = _connectedHere;
    showChannelContextMenu(
      context,
      ref,
      channel: widget.channel,
      spaceId: spaceId,
      canManageChannels: widget.canManageChannels,
      globalPosition: position,
      // Touch has no hover, so the sheet carries the join/disconnect action.
      leadingEntries: [
        if (_isVoice && !connected)
          AccordMenuEntry(
            label: 'Join Voice',
            icon: Icons.call,
            onSelected: _joinVoice,
          ),
        if (_isVoice && connected)
          AccordMenuEntry(
            label: 'Disconnect',
            icon: Icons.call_end,
            destructive: true,
            onSelected: () =>
                ref.read(voiceControllerProvider.notifier).leave(),
          ),
        if (_isVoice) const AccordMenuEntry.divider(),
      ],
    );
  }

  IconData get _glyph {
    switch (widget.channel.type) {
      case 'voice':
        return Icons.volume_up;
      case 'forum':
        return Icons.forum;
      case 'announcement':
        return Icons.campaign;
      case 'arcade':
        return Icons.sports_esports_outlined;
      default:
        return Icons.tag;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final channel = widget.channel;
    final isVoice = channel.type == 'voice';
    final enabled =
        isVoice ||
        channel.type == 'arcade' ||
        channel.type == 'text' ||
        channel.type == 'forum' ||
        channel.type == 'announcement';
    final activeKey = ref.watch(
      connectionsControllerProvider.select((s) => s.activeKey),
    );
    // A channel set to `nothing` is silenced outright: no pip, no badge, no
    // bold name (its unread state is kept, so restoring the level restores the
    // indicator). A muted *space* still shows unread inside itself — that mute
    // only suppresses the rail roll-up.
    final level = activeKey == null
        ? null
        : ref.watch(
            settingsControllerProvider.select(
              (s) => s.channelNotificationLevel(activeKey, channel.id),
            ),
          );
    final channelLevels = {if (level != null) channel.id: level};
    final (unread: isUnread, :mentions) = activeKey == null
        ? (unread: false, mentions: 0)
        : ref.watch(
            readStateControllerProvider(activeKey).select(
              (readState) => (
                unread: readState.isUnreadVisible(
                  channel.id,
                  channelLevels: channelLevels,
                ),
                mentions: readState.visibleMentionCount(
                  channel.id,
                  channelLevels: channelLevels,
                ),
              ),
            ),
          );
    final unread = isUnread && !widget.selected;

    // Voice extras: green tint + count when anyone is present / we're connected.
    final connectedHere =
        isVoice &&
        ref.watch(
          voiceControllerProvider.select((v) => v.channelId == channel.id),
        );
    final voiceCount = isVoice
        ? ref.watch(
            voiceStatesControllerProvider(
              ref.readActiveServerKey() ?? '',
            ).select((cache) => voiceUserCount(cache, channel.id)),
          )
        : 0;
    final iconColor = connectedHere
        ? colors.green
        : (enabled ? colors.dirtyWhite : colors.gray);

    final tileRow = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        child: Material(
          color: widget.selected ? colors.darkGray : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: enabled ? _handleTap : null,
            onLongPress: () => _showMenu(null),
            onSecondaryTapUp: (d) => _showMenu(d.globalPosition),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  Icon(_glyph, size: 18, color: iconColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      channel.name ?? channel.id,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                        color: enabled
                            ? (unread ? Colors.white : colors.dirtyWhite)
                            : colors.gray,
                        fontWeight: unread
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (channel.type == 'arcade' &&
                      activeKey != null &&
                      widget.spaceId != null)
                    ArcadeActivityBadge(
                      serverKey: activeKey,
                      spaceId: widget.spaceId!,
                      channelId: channel.id,
                    )
                  else if (isVoice && voiceCount > 0)
                    Text(
                      '$voiceCount',
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall!.copyWith(color: colors.gray),
                    )
                  else if (mentions > 0)
                    _MentionBadge(count: mentions)
                  else if (unread)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  // Selecting a voice channel only opens its lobby, so the row
                  // carries an explicit join (#202). Hover-only to keep the
                  // list quiet; touch users get the same action from the
                  // long-press menu, or by double-tapping the row.
                  if (isVoice &&
                      !connectedHere &&
                      _hovered &&
                      widget.spaceId != null) ...[
                    const SizedBox(width: 4),
                    Tooltip(
                      message: 'Join Voice',
                      child: InkWell(
                        onTap: _joinVoice,
                        child: Icon(Icons.call, size: 14, color: colors.green),
                      ),
                    ),
                  ],
                  if (widget.onEdit != null && _hovered) ...[
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: widget.onEdit,
                      child: Icon(Icons.settings, size: 14, color: colors.gray),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (!isVoice) return tileRow;
    return OnboardingAnchor(
      anchor: OnboardingAnchorId.voiceChannel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tileRow,
          VoiceParticipantList(channelId: channel.id, spaceId: widget.spaceId),
        ],
      ),
    );
  }
}

/// Red pill rendering the mention count for a channel (or rolled up across a
/// space's channels in the rail). Caps at "99+".
class _MentionBadge extends StatelessWidget {
  const _MentionBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final text = count > 99 ? '99+' : count.toString();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFED4245),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
