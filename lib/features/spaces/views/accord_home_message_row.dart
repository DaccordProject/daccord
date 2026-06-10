part of 'accord_home.dart';

class _MessageRow extends ConsumerStatefulWidget {
  const _MessageRow({
    required this.message,
    required this.channelId,
    required this.spaceId,
    required this.isOwn,
    required this.mentionsMe,
    required this.canManageMessages,
    required this.onReply,
    required this.selecting,
    required this.selected,
    required this.onToggleSelected,
    this.onLongPressSelect,
    this.grouped = false,
    this.author,
    this.authorUser,
    this.nameColor,
  });

  final AccordMessage message;
  final String channelId;

  /// Whether this message continues a group from the same author (see
  /// [_isGrouped]). Grouped rows hide the avatar/name/timestamp header and show
  /// the timestamp in the avatar gutter on hover instead.
  final bool grouped;

  /// Whether the current user can pin/unpin in this channel.
  final bool canManageMessages;

  /// Starts a reply to this message (sets the composer's reply target).
  final VoidCallback onReply;

  /// The space this message belongs to, for opening the author's profile
  /// popout. `null` in contexts without a space (e.g. DMs, not yet supported).
  final String? spaceId;

  /// Whether this message belongs to the current user (gates edit/delete).
  final bool isOwn;

  /// Whether the current user is mentioned by this message (drives highlight).
  final bool mentionsMe;

  /// Whether the pane is in bulk-select mode. While true the row hides its
  /// hover actions, shows a selection checkbox, and a tap toggles selection.
  final bool selecting;

  /// Whether this message is currently selected for bulk deletion.
  final bool selected;

  /// Toggles this message's selection (used while [selecting]).
  final VoidCallback onToggleSelected;

  /// Enters bulk-select mode with this message selected. Null when the current
  /// user lacks `manage_messages` (long-press then does nothing).
  final VoidCallback? onLongPressSelect;

  /// The resolved member for [AccordMessage.authorId], if the space's member
  /// cache has loaded. `null` falls back to [authorUser], then the raw ID.
  final AccordMember? author;

  /// The author resolved from the on-demand user cache, used when the author
  /// isn't in the space's loaded member page. `null` falls back to the raw ID.
  final AccordUser? authorUser;

  /// The author's highest colored-role color, or null for the default color.
  final Color? nameColor;

  @override
  ConsumerState<_MessageRow> createState() => _MessageRowState();
}

class _MessageRowState extends ConsumerState<_MessageRow> {
  bool _hovered = false;
  bool _editing = false;
  bool _busy = false;
  TextEditingController? _editController;

  AccordMessage get _message => widget.message;

  @override
  void dispose() {
    _editController?.dispose();
    super.dispose();
  }

  String get _time {
    final dt = DateTime.tryParse(_message.timestamp);
    if (dt == null) return '';
    final local = dt.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  // intl isn't a dependency, so the full timestamp shown in the tooltip is
  // formatted by hand. Example: "Monday, 5 June 2026 at 14:30".
  String get _fullTime {
    final dt = DateTime.tryParse(_message.timestamp);
    if (dt == null) return '';
    final local = dt.toLocal();
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday', //
    ];
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June', 'July',
      'August', 'September', 'October', 'November', 'December', //
    ];
    final weekday = weekdays[local.weekday - 1];
    final month = months[local.month - 1];
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$weekday, ${local.day} $month ${local.year} at $hh:$mm';
  }

  /// Nickname → user display name → username → "Unknown". Falls back to the
  /// on-demand user cache when the author isn't in the loaded member page, and
  /// never shows the raw snowflake ID (the user controller fetches asynchronously
  /// — by the next rebuild a real name resolves; "Unknown" is the brief gap).
  String get _authorName {
    if (widget.author != null) {
      return accordMemberName(widget.author, fallback: 'Unknown');
    }
    if (widget.authorUser != null) {
      return accordUserName(widget.authorUser, fallback: 'Unknown');
    }
    return 'Unknown';
  }

  String get _initial {
    final name = _authorName.trim();
    if (name.isEmpty) return '?';
    return name.substring(0, 1).toUpperCase();
  }

  AccordClient? get _client => ref.read(
    accordAuthProvider.select((s) => s is AccordAuthLoggedIn ? s.client : null),
  );

  void _startEdit() {
    setState(() {
      _editing = true;
      _editController = TextEditingController(text: _message.content);
    });
  }

  void _cancelEdit() {
    setState(() {
      _editing = false;
      _editController?.dispose();
      _editController = null;
    });
  }

  Future<void> _saveEdit() async {
    final client = _client;
    final text = _editController?.text ?? '';
    if (client == null || text.trim().isEmpty || _busy) return;
    setState(() => _busy = true);
    final ok = await ref
        .read(accordMessagesControllerProvider(widget.channelId).notifier)
        .edit(client, _message.id, text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) _cancelEdit();
  }

  void _openPopout() {
    final spaceId = widget.spaceId;
    if (spaceId == null) return;
    showAccordMemberPopout(
      context,
      spaceId: spaceId,
      userId: _message.authorId,
    );
  }

  /// Opens a popup listing the users who added [reaction], lazy-loaded.
  void _showReactors(AccordReaction reaction) {
    showDialog<void>(
      context: context,
      builder: (_) => _ReactorsDialog(
        channelId: widget.channelId,
        messageId: _message.id,
        emojiName: reaction.emoji['name']?.toString() ?? '',
        emojiId: reaction.emoji['id']?.toString(),
      ),
    );
  }

  void _toggleReaction(String emojiName, {String? emojiId}) {
    final client = _client;
    if (client == null) return;
    ref
        .read(accordMessagesControllerProvider(widget.channelId).notifier)
        .toggleReaction(client, _message.id, emojiName, emojiId: emojiId);
  }

  Future<void> _openReactionPicker() async {
    final pick = await showAccordEmojiPicker(context, spaceId: widget.spaceId);
    if (pick == null || !mounted) return;
    _toggleReaction(pick.name, emojiId: pick.id);
  }

  Future<void> _togglePin() async {
    final client = _client;
    if (client == null) return;
    final controller = ref.read(
      accordMessagesControllerProvider(widget.channelId).notifier,
    );
    if (_message.pinned) {
      await controller.unpin(client, _message.id);
    } else {
      await controller.pin(client, _message.id);
    }
  }

  Future<void> _delete() async {
    final client = _client;
    if (client == null || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message'),
        content: const Text('This message will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    await ref
        .read(accordMessagesControllerProvider(widget.channelId).notifier)
        .delete(client, _message.id);
    // Row disappears on success; if it failed we just re-enable.
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    // Compact density tightens vertical spacing and shrinks the avatar gutter.
    final compact = ref.watch(
      settingsControllerProvider.select((s) => s.compactMode),
    );
    final topGap = widget.grouped
        ? (compact ? 0.0 : 1.0)
        : (compact ? 3.0 : 6.0);
    final bottomGap = compact ? 3.0 : 6.0;
    final avatarRadius = compact ? 14.0 : 18.0;
    final gutter = compact ? 8.0 : 12.0;
    final cdnUrl = ref.watch(
      accordAuthProvider.select(
        (s) => s is AccordAuthLoggedIn ? s.session.server.cdnUrl : null,
      ),
    );
    final avatarUrl = widget.author != null
        ? accordMemberAvatarUrl(widget.author, cdnUrl)
        : accordAvatarUrl(widget.authorUser, cdnUrl);
    final avatarBg = accordAvatarColor(
      widget.author?.user ?? widget.authorUser,
      _message.authorId,
    );
    final tappable = widget.spaceId != null;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onLongPressStart:
            widget.selecting ? null : (d) => _showActionsMenu(d.globalPosition),
        onSecondaryTapUp:
            widget.selecting ? null : (d) => _showActionsMenu(d.globalPosition),
        onTap: widget.selecting ? widget.onToggleSelected : null,
        child: Container(
          padding: widget.mentionsMe
              ? EdgeInsets.fromLTRB(13, topGap, 6, bottomGap)
              : EdgeInsets.only(top: topGap, bottom: bottomGap),
          decoration: widget.selected
              ? BoxDecoration(color: colors.primary.withValues(alpha: 0.14))
              : widget.mentionsMe
              ? BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.08),
                  border: Border(
                    left: BorderSide(color: colors.primary, width: 3),
                  ),
                )
              : null,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.selecting) ...[
                Checkbox(
                  value: widget.selected,
                  onChanged: (_) => widget.onToggleSelected(),
                ),
                const SizedBox(width: 4),
              ],
              if (widget.grouped)
                SizedBox(
                  width: avatarRadius * 2,
                  child: Opacity(
                    opacity: _hovered ? 1 : 0,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Tooltip(
                        message: _fullTime,
                        child: Text(
                          _time,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall!.copyWith(
                            color: colors.gray,
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              else
                _MaybeTappable(
                  enabled: tappable,
                  onTap: _openPopout,
                  child: CircleAvatar(
                    radius: avatarRadius,
                    backgroundColor: avatarBg,
                    foregroundImage: avatarUrl == null
                        ? null
                        : CachedNetworkImageProvider(avatarUrl),
                    child: Text(
                      _initial,
                      style: theme.textTheme.titleSmall!.copyWith(
                        color: accordOnColor(avatarBg),
                      ),
                    ),
                  ),
                ),
              SizedBox(width: gutter),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_message.replyTo != null) _buildReplyPreview(colors),
                    if (!widget.grouped)
                      Row(
                        children: [
                          if (_message.pinned) ...[
                            Icon(Icons.push_pin, size: 12, color: colors.gray),
                            const SizedBox(width: 4),
                          ],
                          _MaybeTappable(
                            enabled: tappable,
                            onTap: _openPopout,
                            child: Text(
                              _authorName,
                              style: theme.textTheme.titleSmall!.copyWith(
                                color: widget.nameColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Tooltip(
                            message: _fullTime,
                            child: Text(
                              _time,
                              style: theme.textTheme.labelMedium!.copyWith(
                                color: colors.gray,
                              ),
                            ),
                          ),
                          if (_message.editedAt != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              '(edited)',
                              style: theme.textTheme.labelSmall!.copyWith(
                                color: colors.gray,
                              ),
                            ),
                          ],
                        ],
                      ),
                    if (_editing)
                      _buildEditor(theme, colors)
                    else if (_message.content.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: AccordMessageContent(
                          content: _message.content,
                          spaceId: widget.spaceId,
                        ),
                      ),
                    for (final attachment in _message.attachments)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: _buildAttachment(attachment, cdnUrl, theme),
                      ),
                    for (final embed in _message.embeds)
                      AccordEmbedBox(embed: embed, cdnUrl: cdnUrl),
                    if ((_message.reactions ?? const []).isNotEmpty)
                      _buildReactions(theme, colors, cdnUrl),
                    if (_message.replyCount > 0)
                      _buildThreadChip(theme, colors),
                  ],
                ),
              ),
              // Hover actions are mouse-driven (revealed by [_hovered]) and have
              // no affordance on touch, where `Opacity` would still reserve their
              // width and squeeze the message content into a narrow column. Omit
              // them on mobile so the content uses the full row width.
              if (!_editing &&
                  !widget.selecting &&
                  shouldUseDesktopLayout(context))
                Opacity(
                  opacity: _hovered ? 1 : 0,
                  child: Row(
                    children: [
                      _ReactButton(onPressed: _openReactionPicker),
                      IconButton(
                        tooltip: 'Reply',
                        onPressed: widget.onReply,
                        icon: Icon(Icons.reply, size: 18, color: colors.gray),
                      ),
                      IconButton(
                        tooltip: 'Thread',
                        onPressed: _openThread,
                        icon: Icon(
                          Icons.forum_outlined,
                          size: 18,
                          color: colors.gray,
                        ),
                      ),
                      if (widget.isOwn ||
                          widget.canManageMessages ||
                          (!widget.isOwn && widget.spaceId != null))
                        _MessageActions(
                          canEdit: widget.isOwn,
                          canDelete: widget.isOwn || widget.canManageMessages,
                          canPin: widget.canManageMessages,
                          canReport: !widget.isOwn && widget.spaceId != null,
                          pinned: _message.pinned,
                          onEdit: _startEdit,
                          onDelete: _delete,
                          onTogglePin: _togglePin,
                          onReport: _report,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openThread() => showAccordThread(
    context,
    channelId: widget.channelId,
    spaceId: widget.spaceId,
    root: _message,
  );

  void _report() {
    final spaceId = widget.spaceId;
    if (spaceId == null) return;
    showReportDialog(
      context,
      spaceId: spaceId,
      targetType: 'message',
      targetId: _message.id,
      channelId: widget.channelId,
    );
  }

  /// The long-press (mobile) / right-click (desktop) message menu. Bulk-select
  /// lives here as one entry rather than being the long-press itself, so the
  /// per-message actions stay reachable on touch.
  void _showActionsMenu([Offset? position]) {
    if (_editing) return;
    final canDelete = widget.isOwn || widget.canManageMessages;
    final canReport = !widget.isOwn && widget.spaceId != null;
    final entries = <AccordMenuEntry>[
      AccordMenuEntry(
        label: 'Add reaction',
        icon: Icons.add_reaction_outlined,
        onSelected: _openReactionPicker,
      ),
      AccordMenuEntry(
        label: 'Reply',
        icon: Icons.reply,
        onSelected: widget.onReply,
      ),
      AccordMenuEntry(
        label: 'Thread',
        icon: Icons.forum_outlined,
        onSelected: _openThread,
      ),
      if (_message.content.isNotEmpty)
        AccordMenuEntry(
          label: 'Copy text',
          icon: Icons.copy_outlined,
          onSelected: () =>
              Clipboard.setData(ClipboardData(text: _message.content)),
        ),
      if (widget.isOwn)
        AccordMenuEntry(
          label: 'Edit',
          icon: Icons.edit_outlined,
          onSelected: _startEdit,
        ),
      if (widget.canManageMessages)
        AccordMenuEntry(
          label: _message.pinned ? 'Unpin' : 'Pin',
          icon: _message.pinned ? Icons.push_pin_outlined : Icons.push_pin,
          onSelected: _togglePin,
        ),
      if (canDelete)
        AccordMenuEntry(
          label: 'Delete',
          icon: Icons.delete_outline,
          destructive: true,
          onSelected: _delete,
        ),
      if (canReport)
        AccordMenuEntry(
          label: 'Report',
          icon: Icons.flag_outlined,
          onSelected: _report,
        ),
      if (widget.onLongPressSelect != null) ...[
        const AccordMenuEntry.divider(),
        AccordMenuEntry(
          label: 'Select messages',
          icon: Icons.checklist,
          onSelected: widget.onLongPressSelect,
        ),
      ],
    ];

    showAccordContextMenu(
      context,
      entries: entries,
      globalPosition: position,
      title: _authorName,
    );
  }

  Widget _buildThreadChip(ThemeData theme, BonfireThemeExtension colors) {
    final count = _message.replyCount;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: _openThread,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, size: 14, color: colors.primary),
              const SizedBox(width: 6),
              Text(
                '$count ${count == 1 ? 'reply' : 'replies'}',
                style: theme.textTheme.labelMedium!.copyWith(
                  color: colors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReactions(
    ThemeData theme,
    BonfireThemeExtension colors,
    String? cdnUrl,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final reaction in _message.reactions!)
            _ReactionPill(
              reaction: reaction,
              cdnUrl: cdnUrl,
              onTap: () => _toggleReaction(
                reaction.emoji['name']?.toString() ?? '',
                emojiId: reaction.emoji['id']?.toString(),
              ),
              onShowReactors: () => _showReactors(reaction),
            ),
        ],
      ),
    );
  }

  /// A compact "↩ Name preview" line above a reply message, resolving the
  /// referenced message from the loaded channel cache when available.
  Widget _buildReplyPreview(BonfireThemeExtension colors) {
    final theme = Theme.of(context);
    final messages = ref.read(
      accordMessagesControllerProvider(widget.channelId),
    );
    final referenced = messages?.firstWhereOrNull(
      (m) => m.id == _message.replyTo,
    );
    String name = 'Unknown';
    String preview = '';
    if (referenced != null) {
      final members = widget.spaceId == null
          ? null
          : ref.read(accordMembersControllerProvider(widget.spaceId!));
      name = accordMemberName(
        members?[referenced.authorId],
        fallback: referenced.authorId,
      );
      preview = referenced.content.isEmpty
          ? '(attachment)'
          : referenced.content;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 2, left: 2),
      child: Row(
        children: [
          Icon(Icons.reply, size: 12, color: colors.gray),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              preview.isEmpty ? name : '$name  $preview',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium!.copyWith(color: colors.gray),
            ),
          ),
        ],
      ),
    );
  }

  /// Renders one attachment inline: tappable image (→ lightbox), video player,
  /// audio player, or a filename chip for other types.
  Widget _buildAttachment(
    AccordAttachment attachment,
    String? cdnUrl,
    ThemeData theme,
  ) {
    final url = _attachmentUrl(attachment, cdnUrl);
    if (_isImageAttachment(attachment)) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => showImageLightbox(context, url),
          child: _ImageAttachment(
            url: url,
            width: _asDouble(attachment.width),
            height: _asDouble(attachment.height),
          ),
        ),
      );
    }
    if (_isVideoAttachment(attachment)) {
      return InlineVideoPlayer(
        url: url,
        filename: attachment.filename,
        width: _asDouble(attachment.width),
        height: _asDouble(attachment.height),
      );
    }
    if (_isAudioAttachment(attachment)) {
      return InlineAudioPlayer(url: url, filename: attachment.filename);
    }
    return Text('📎 ${attachment.filename}', style: theme.textTheme.bodyMedium);
  }

  Widget _buildEditor(ThemeData theme, BonfireThemeExtension colors) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _editController,
            autofocus: true,
            enabled: !_busy,
            minLines: 1,
            maxLines: 6,
            style: theme.textTheme.bodyLarge,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: colors.darkGray,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (_) => _saveEdit(),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              TextButton(
                onPressed: _busy ? null : _cancelEdit,
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: _busy ? null : _saveEdit,
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Wraps [child] in a click-to-open gesture (with a pointer cursor) when
/// [enabled]; otherwise renders the child untouched. Used so message authors are
/// only tappable inside a space (where a profile popout makes sense).
class _MaybeTappable extends StatelessWidget {
  const _MaybeTappable({
    required this.enabled,
    required this.onTap,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: child),
    );
  }
}

class _MessageActions extends StatelessWidget {
  const _MessageActions({
    required this.canEdit,
    required this.canDelete,
    required this.canPin,
    required this.canReport,
    required this.pinned,
    required this.onEdit,
    required this.onDelete,
    required this.onTogglePin,
    required this.onReport,
  });

  final bool canEdit;
  final bool canDelete;
  final bool canPin;
  final bool canReport;
  final bool pinned;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTogglePin;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return PopupMenuButton<String>(
      tooltip: 'Message actions',
      icon: Icon(Icons.more_horiz, size: 18, color: colors.gray),
      onSelected: (value) {
        switch (value) {
          case 'edit':
            onEdit();
          case 'delete':
            onDelete();
          case 'pin':
            onTogglePin();
          case 'report':
            onReport();
        }
      },
      itemBuilder: (context) => [
        if (canPin)
          PopupMenuItem(value: 'pin', child: Text(pinned ? 'Unpin' : 'Pin')),
        if (canEdit) const PopupMenuItem(value: 'edit', child: Text('Edit')),
        if (canDelete)
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        if (canReport)
          const PopupMenuItem(value: 'report', child: Text('Report')),
      ],
    );
  }
}

/// Opens the full emoji picker to add a reaction to the message.
/// A bell toggle in the channel header that mutes/unmutes notifications for the
/// channel. Loads the user's muted-channel list once per channel and flips it
/// optimistically on tap.
class _MuteButton extends ConsumerStatefulWidget {
  const _MuteButton({required this.channelId});

  final String channelId;

  @override
  ConsumerState<_MuteButton> createState() => _MuteButtonState();
}

class _MuteButtonState extends ConsumerState<_MuteButton> {
  bool? _muted;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_MuteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channelId != widget.channelId) {
      _muted = null;
      _load();
    }
  }

  AccordClient? get _client => ref.read(
    accordAuthProvider.select((s) => s is AccordAuthLoggedIn ? s.client : null),
  );

  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    final result = await client.users.listMutes();
    if (!mounted) return;
    final data = result.data;
    final ids = data is List
        ? data.map((e) => e.toString()).toSet()
        : const <String>{};
    setState(() => _muted = ids.contains(widget.channelId));
  }

  Future<void> _toggle() async {
    final client = _client;
    if (client == null || _busy || _muted == null) return;
    final next = !_muted!;
    setState(() {
      _busy = true;
      _muted = next;
    });
    final result = next
        ? await client.channels.mute(widget.channelId)
        : await client.channels.unmute(widget.channelId);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!result.ok) _muted = !next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final muted = _muted ?? false;
    // Per-channel notification level lives client-side (mirrors the reference
    // client). Mute is server-side and a separate axis — "Mute" silences the
    // gateway-level mute flag, while All / Mentions / Nothing tunes our local
    // notification gating.
    final level = ref.watch(
      settingsControllerProvider.select(
        (s) => s.channelNotificationLevel(widget.channelId),
      ),
    );
    final levelLabel = level == null
        ? 'Mentions (default)'
        : level == AccordSettings.channelNotifAll
        ? 'All messages'
        : level == AccordSettings.channelNotifMentions
        ? 'Mentions only'
        : 'Nothing';
    return PopupMenuButton<_NotifAction>(
      tooltip: 'Notification settings — $levelLabel',
      icon: Icon(
        muted
            ? Icons.notifications_off
            : (level == AccordSettings.channelNotifNothing
                  ? Icons.notifications_paused
                  : (level == AccordSettings.channelNotifAll
                        ? Icons.notifications_active
                        : Icons.notifications_none)),
        size: 18,
        color: colors.dirtyWhite,
      ),
      onSelected: (action) {
        switch (action) {
          case _NotifAction.levelDefault:
            ref
                .read(settingsControllerProvider.notifier)
                .setChannelNotificationLevel(widget.channelId, null);
            break;
          case _NotifAction.levelAll:
            ref
                .read(settingsControllerProvider.notifier)
                .setChannelNotificationLevel(
                  widget.channelId,
                  AccordSettings.channelNotifAll,
                );
            break;
          case _NotifAction.levelMentions:
            ref
                .read(settingsControllerProvider.notifier)
                .setChannelNotificationLevel(
                  widget.channelId,
                  AccordSettings.channelNotifMentions,
                );
            break;
          case _NotifAction.levelNothing:
            ref
                .read(settingsControllerProvider.notifier)
                .setChannelNotificationLevel(
                  widget.channelId,
                  AccordSettings.channelNotifNothing,
                );
            break;
          case _NotifAction.toggleMute:
            _toggle();
            break;
        }
      },
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: _NotifAction.levelDefault,
          checked: level == null,
          child: const Text('Use default'),
        ),
        CheckedPopupMenuItem(
          value: _NotifAction.levelAll,
          checked: level == AccordSettings.channelNotifAll,
          child: const Text('All messages'),
        ),
        CheckedPopupMenuItem(
          value: _NotifAction.levelMentions,
          checked: level == AccordSettings.channelNotifMentions,
          child: const Text('Only @mentions'),
        ),
        CheckedPopupMenuItem(
          value: _NotifAction.levelNothing,
          checked: level == AccordSettings.channelNotifNothing,
          child: const Text('Nothing'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _NotifAction.toggleMute,
          enabled: _muted != null,
          child: Text(muted ? 'Unmute channel' : 'Mute channel'),
        ),
      ],
    );
  }
}

enum _NotifAction {
  levelDefault,
  levelAll,
  levelMentions,
  levelNothing,
  toggleMute,
}

class _ReactButton extends StatelessWidget {
  const _ReactButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return IconButton(
      tooltip: 'Add reaction',
      onPressed: onPressed,
      icon: Icon(Icons.add_reaction_outlined, size: 18, color: colors.gray),
    );
  }
}

class _ReactionPill extends StatelessWidget {
  const _ReactionPill({
    required this.reaction,
    required this.onTap,
    required this.onShowReactors,
    this.cdnUrl,
  });

  final AccordReaction reaction;
  final VoidCallback onTap;

  /// Long-press / right-click: reveal who reacted.
  final VoidCallback onShowReactors;
  final String? cdnUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final rawName = reaction.emoji['name']?.toString() ?? '';
    final rawId = reaction.emoji['id']?.toString();
    // A custom emoji whose source didn't split it arrives as name=`name:id`,
    // id=null; recover the id so we render the image instead of literal text.
    final parsed = parseEmojiToken(rawName);
    final id = rawId ?? parsed.id;
    final name = rawId != null ? rawName : parsed.name;
    final mine = reaction.includesMe;
    return Material(
      color: mine ? colors.primary.withValues(alpha: 0.25) : colors.darkGray,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onShowReactors,
        onSecondaryTap: onShowReactors,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: mine ? colors.primary : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (id != null)
                CachedNetworkImage(
                  imageUrl: AccordCDN.emoji(id, cdnUrl: cdnUrl ?? ''),
                  width: 16,
                  height: 16,
                  fit: BoxFit.contain,
                  errorWidget: (_, _, _) =>
                      Text(name, style: const TextStyle(fontSize: 14)),
                )
              else
                // Unicode reaction: `name` is the shortcode (e.g. `hamburger`),
                // not the glyph — resolve it to the actual emoji character.
                Text(
                  resolveEmojiGlyph(name),
                  style: const TextStyle(fontSize: 16),
                ),
              const SizedBox(width: 4),
              Text(
                '${reaction.count}',
                style: theme.textTheme.labelMedium!.copyWith(
                  color: colors.dirtyWhite,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A popup listing the users who reacted with a given emoji, lazy-loaded when
/// opened (reactor lists aren't prefetched per message). Ports the reference
/// client's reactor reveal.
class _ReactorsDialog extends ConsumerStatefulWidget {
  const _ReactorsDialog({
    required this.channelId,
    required this.messageId,
    required this.emojiName,
    required this.emojiId,
  });

  final String channelId;
  final String messageId;
  final String emojiName;
  final String? emojiId;

  @override
  ConsumerState<_ReactorsDialog> createState() => _ReactorsDialogState();
}

class _ReactorsDialogState extends ConsumerState<_ReactorsDialog> {
  List<AccordUser>? _users;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = ref.read(
      accordAuthProvider.select(
        (s) => s is AccordAuthLoggedIn ? s.client : null,
      ),
    );
    if (client == null) {
      setState(() => _users = const []);
      return;
    }
    final users = await ref
        .read(accordMessagesControllerProvider(widget.channelId).notifier)
        .reactionUsers(
          client,
          widget.messageId,
          widget.emojiName,
          emojiId: widget.emojiId,
        );
    if (mounted) setState(() => _users = users);
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final cdnUrl = ref.watch(
      accordAuthProvider.select(
        (s) => s is AccordAuthLoggedIn ? s.session.server.cdnUrl : null,
      ),
    );
    final users = _users;
    return AlertDialog(
      title: Text(
        widget.emojiId == null
            ? 'Reacted with ${resolveEmojiGlyph(widget.emojiName)}'
            : 'Reacted with :${widget.emojiName}:',
      ),
      content: SizedBox(
        width: 300,
        child: users == null
            ? const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              )
            : users.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No one yet.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium!.copyWith(color: colors.gray),
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final user in users)
                    ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: accordAvatarColor(user, user.id),
                        foregroundImage: accordAvatarUrl(user, cdnUrl) == null
                            ? null
                            : CachedNetworkImageProvider(
                                accordAvatarUrl(user, cdnUrl)!,
                              ),
                        child: Text(
                          accordUserName(
                            user,
                            fallback: '?',
                          ).characters.first.toUpperCase(),
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                      title: Text(
                        accordUserName(user, fallback: user.id),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
