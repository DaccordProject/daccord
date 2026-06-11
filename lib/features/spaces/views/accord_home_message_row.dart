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
    final spaceId = widget.spaceId;
    final customEmoji = spaceId == null
        ? const <AccordEmoji>[]
        : ref.watch(accordEmojisControllerProvider(spaceId)) ??
              const <AccordEmoji>[];
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final reaction in _message.reactions!)
            _ReactionPill(
              reaction: reaction,
              imageUrl: _reactionEmojiUrl(reaction, customEmoji, cdnUrl),
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

  /// Resolves a custom reaction's image URL. Reactions only carry `{id, name}`,
  /// so the authoritative `image_url` (with the space segment and real
  /// extension) is looked up from the space's emoji catalog by id; the bare CDN
  /// path is a last resort. Null for unicode reactions.
  String? _reactionEmojiUrl(
    AccordReaction reaction,
    List<AccordEmoji> customEmoji,
    String? cdnUrl,
  ) {
    final rawId = reaction.emoji['id']?.toString();
    final id =
        rawId ?? parseEmojiToken(reaction.emoji['name']?.toString() ?? '').id;
    if (id == null) return null;
    final match = customEmoji.firstWhereOrNull((e) => e.id == id);
    if (match != null && match.imageUrl.isNotEmpty) {
      return AccordCDN.resolvePath(match.imageUrl, cdnUrl: cdnUrl ?? '');
    }
    return AccordCDN.emoji(
      id,
      format: match?.animated ?? false ? 'gif' : 'png',
      cdnUrl: cdnUrl ?? '',
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
