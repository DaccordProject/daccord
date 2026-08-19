part of 'message_pane.dart';

class _MessageRow extends ConsumerStatefulWidget {
  const _MessageRow({
    super.key,
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
    this.narrow = false,
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

  /// Whether the row is rendered in a narrow column (the voice channel's chat
  /// panel). An inline hover action bar reserves its full width even while
  /// invisible, which in a ~340px panel would leave the message itself a few
  /// dozen pixels; a narrow row floats the same bar over its top-right corner
  /// instead. Everything else about the row is unchanged.
  final bool narrow;

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

  /// Whether the row's "⋯" actions menu is open. Only meaningful when [narrow],
  /// where the action bar is mounted on hover alone — see [_menuStateChanged].
  bool _menuOpen = false;
  bool _editing = false;
  bool _busy = false;
  TextEditingController? _editController;

  /// The message the inline editor was opened on. The edit is committed against
  /// this id rather than the currently-bound one, so an in-progress edit can
  /// never be saved onto a neighbouring message.
  String? _editingMessageId;

  /// The message this row is currently bound to.
  ///
  /// Only ever read synchronously — during `build`, or at the very top of a
  /// handler. **Never read it after an `await`**: a [State] outlives the widget
  /// it was built from, so while a dialog/picker is open this row can be re-bound
  /// to a different message (the `mounted` guard does not catch that, the State
  /// really is still mounted). Every async handler therefore takes the id it
  /// captured up front. See #198.
  AccordMessage get _message => widget.message;

  @override
  void dispose() {
    _editController?.dispose();
    super.dispose();
  }

  // Bare HH:MM. Used in the grouped-message gutter, a fixed narrow slot where a
  // full date wouldn't fit (grouped rows are within minutes of their header).
  String get _clock {
    final dt = DateTime.tryParse(_message.timestamp);
    if (dt == null) return '';
    return messageClockString(dt.toLocal());
  }

  // The header time is date-aware so a message from days ago isn't mistaken for
  // a recent one: today shows just the time, yesterday is prefixed, earlier this
  // week shows the weekday, and older messages get the calendar date. intl isn't
  // a dependency, so this is formatted by hand.
  String get _time {
    final dt = DateTime.tryParse(_message.timestamp);
    if (dt == null) return '';
    return messageTimeString(dt.toLocal());
  }

  // Full timestamp shown in the tooltip, e.g. "Monday, 5 June 2026 at 14:30".
  String get _fullTime {
    final dt = DateTime.tryParse(_message.timestamp);
    if (dt == null) return '';
    return messageTimestampString(dt.toLocal());
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

  String get _initial => accordInitial(_authorName);

  /// The home domain of a remote (federated) author, or null when local. Drives
  /// the federated-origin badge so remote authors are visually distinguishable.
  String? get _authorOrigin =>
      accordMemberOrigin(widget.author) ??
      accordUserOrigin(widget.authorUser) ??
      _message.origin;

  AccordClient? get _client => ref.accordClient;

  void _startEdit(AccordMessage message) {
    setState(() {
      _editing = true;
      _editingMessageId = message.id;
      _editController = TextEditingController(text: message.content);
    });
  }

  void _cancelEdit() {
    setState(() {
      _editing = false;
      _editingMessageId = null;
      _editController?.dispose();
      _editController = null;
    });
  }

  Future<void> _saveEdit() async {
    final client = _client;
    final raw = _editController?.text ?? '';
    // Edits convert emoticons too, matching the send path — otherwise fixing a
    // typo would silently downgrade an already-converted glyph back to ASCII.
    final text =
        ref.read(settingsControllerProvider.select((s) => s.convertEmoticons))
        ? applyEmoticons(raw)
        : raw;
    // Commit against the message the editor was opened on, captured before the
    // round-trip.
    final messageId = _editingMessageId ?? _message.id;
    if (client == null || text.trim().isEmpty || _busy) return;
    setState(() => _busy = true);
    final ok = await ref
        .read(accordMessagesControllerProvider(widget.channelId).notifier)
        .edit(client, messageId, text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) _cancelEdit();
  }

  void _openPopout(String authorId) {
    final spaceId = widget.spaceId;
    if (spaceId == null) return;
    showAccordMemberPopout(context, spaceId: spaceId, userId: authorId);
  }

  /// Opens a popup listing the users who added [reaction], lazy-loaded.
  void _showReactors(String messageId, AccordReaction reaction) {
    showDialog<void>(
      context: context,
      builder: (_) => _ReactorsDialog(
        channelId: widget.channelId,
        messageId: messageId,
        emojiName: reaction.emoji['name']?.toString() ?? '',
        emojiId: reaction.emoji['id']?.toString(),
      ),
    );
  }

  void _toggleReaction(
    String messageId,
    String emojiName, {
    String? emojiId,
  }) {
    final client = _client;
    if (client == null) return;
    ref
        .read(accordMessagesControllerProvider(widget.channelId).notifier)
        .toggleReaction(client, messageId, emojiName, emojiId: emojiId);
  }

  Future<void> _openReactionPicker(String messageId) async {
    final pick = await showAccordEmojiPicker(context, spaceId: widget.spaceId);
    if (pick == null || !mounted) return;
    _toggleReaction(messageId, pick.name, emojiId: pick.id);
  }

  Future<void> _togglePin(String messageId, {required bool pinned}) async {
    final client = _client;
    if (client == null) return;
    final controller = ref.read(
      accordMessagesControllerProvider(widget.channelId).notifier,
    );
    if (pinned) {
      await controller.unpin(client, messageId);
    } else {
      await controller.pin(client, messageId);
    }
  }

  /// Keeps the floating action bar mounted for as long as its menu is open.
  ///
  /// When [_MessageRow.narrow] the bar is only built while the row is hovered,
  /// but opening a [PopupMenuButton] pushes a modal barrier that ends the hover
  /// — which unmounted the button mid-menu, and Flutter drops the selection
  /// when the button is gone (`if (!mounted) return` in `showButtonMenu`).
  /// Every item in that menu (delete, edit, pin, report) silently did nothing
  /// in the voice channel's chat panel as a result.
  void _menuStateChanged(bool open) {
    if (!mounted) return;
    setState(() => _menuOpen = open);
  }

  Future<void> _delete(String messageId) async {
    final client = _client;
    if (client == null || _busy) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete message',
      message: 'This message will be permanently deleted.',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final ok = await ref
        .read(accordMessagesControllerProvider(widget.channelId).notifier)
        .delete(client, messageId);
    if (!mounted) return;
    // Row disappears on success; if it failed we re-enable and say so, rather
    // than leaving the message sitting there as if nothing had been asked.
    setState(() => _busy = false);
    if (!ok) showInfoSnack(context, 'Failed to delete message');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    // Captured once so every callback this build hands out targets the message
    // that was rendered, never whatever `widget.message` happens to be by the
    // time the callback runs.
    final message = _message;
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
    final cdnUrl = ref.watchCdnUrl();
    final avatarUrl = widget.author != null
        ? accordMemberAvatarUrl(widget.author, cdnUrl)
        : accordAvatarUrl(widget.authorUser, cdnUrl);
    final avatarBg = accordAvatarColor(
      widget.author?.user ?? widget.authorUser,
      message.authorId,
    );
    final tappable = widget.spaceId != null;
    void openPopout() => _openPopout(message.authorId);
    // Hover actions are mouse-driven and have no affordance on touch, where
    // `Opacity` would still reserve their width and squeeze the message content
    // into a narrow column. Omit them on mobile so the content uses the full
    // row width. On desktop they render inline at the end of the row, or —
    // when [narrow] — floated over it (see [_FloatingActionsOverlay]).
    final hoverActions =
        _editing || widget.selecting || !shouldUseDesktopLayout(context)
        ? null
        : _HoverActions(
            // Floated (see below), the bar is only built while hovered, so it
            // doesn't need to fade itself out.
            visible: widget.narrow || _hovered,
            onReact: () => _openReactionPicker(message.id),
            onReply: widget.onReply,
            onThread: () => _openThread(message),
            canEdit: widget.isOwn,
            canDelete: widget.isOwn || widget.canManageMessages,
            canPin: widget.canManageMessages,
            canReport: !widget.isOwn && widget.spaceId != null,
            pinned: message.pinned,
            onEdit: () => _startEdit(message),
            onDelete: () => _delete(message.id),
            onTogglePin: () => _togglePin(message.id, pinned: message.pinned),
            onReport: () => _report(message.id),
            onMenuStateChanged: _menuStateChanged,
          );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: _FloatingActionsOverlay(
        // In the voice chat panel an inline action bar would leave the message
        // a few dozen pixels of width, so the bar floats over the row's
        // top-right corner instead — and only while hovered, so it never covers
        // the text or swallows a click. `_menuOpen` extends that past the
        // hover: the actions menu's barrier ends the hover, and unmounting the
        // button mid-menu loses the selection (see [_menuStateChanged]).
        actions: widget.narrow && (_hovered || _menuOpen) ? hoverActions : null,
        child: GestureDetector(
          // Opaque so the whole row is hit-testable: on mobile a plain-text
          // message renders as a bare RichText with no recognisers, and the
          // surrounding Container is transparent, so with the default
          // `deferToChild` a long-press over the text hits nothing and never
          // fires. Only the avatar (which paints a background) responded before.
          behavior: HitTestBehavior.opaque,
          onLongPressStart: widget.selecting
              ? null
              : (d) => _showActionsMenu(message, d.globalPosition),
          onSecondaryTapUp: widget.selecting
              ? null
              : (d) => _showActionsMenu(message, d.globalPosition),
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
                  _GutterTimestamp(
                    width: avatarRadius * 2,
                    visible: _hovered,
                    clock: _clock,
                    fullTime: _fullTime,
                  )
                else
                  _MaybeTappable(
                    enabled: tappable,
                    onTap: openPopout,
                    child: AccordMemberAvatar(
                      avatarUrl: avatarUrl,
                      initial: _initial,
                      radius: avatarRadius,
                      backgroundColor: avatarBg,
                      initialStyle: theme.textTheme.titleSmall,
                    ),
                  ),
                SizedBox(width: gutter),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (message.replyTo != null)
                        _buildReplyPreview(message, colors),
                      if (!widget.grouped)
                        MessageAuthorHeader(
                          name: _authorName,
                          nameColor: widget.nameColor,
                          // A long name must ellipsize rather than push the
                          // timestamp out of a narrow row.
                          ellipsizeName: true,
                          onNameTap: tappable ? openPopout : null,
                          pinned: message.pinned,
                          origin: _authorOrigin,
                          time: _time,
                          timeTooltip: _fullTime,
                          edited: message.editedAt != null,
                        ),
                      if (_editing)
                        _buildEditor(theme, colors)
                      else if (message.content.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: AccordMessageContent(
                            content: message.content,
                            spaceId: widget.spaceId,
                          ),
                        ),
                      for (final attachment in message.attachments)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: _buildAttachment(attachment, cdnUrl, theme),
                        ),
                      for (final embed in message.embeds)
                        AccordEmbedBox(embed: embed, cdnUrl: cdnUrl),
                      if ((message.reactions ?? const []).isNotEmpty)
                        _buildReactions(message, theme, colors, cdnUrl),
                      if (message.replyCount > 0)
                        _buildThreadChip(message, theme, colors),
                    ],
                  ),
                ),
                if (hoverActions != null && !widget.narrow) hoverActions,
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openThread(AccordMessage message) => showAccordThread(
    context,
    channelId: widget.channelId,
    spaceId: widget.spaceId,
    root: message,
    canManageMessages: widget.canManageMessages,
  );

  void _report(String messageId) {
    final spaceId = widget.spaceId;
    if (spaceId == null) return;
    showReportDialog(
      context,
      spaceId: spaceId,
      targetType: 'message',
      targetId: messageId,
      channelId: widget.channelId,
    );
  }

  /// The long-press (mobile) / right-click (desktop) message menu. Bulk-select
  /// lives here as one entry rather than being the long-press itself, so the
  /// per-message actions stay reachable on touch.
  ///
  /// [message] is captured when the menu opens: the entries' callbacks only run
  /// once the menu has closed (an await), by which point the row may already be
  /// bound to a different message.
  void _showActionsMenu(AccordMessage message, [Offset? position]) {
    if (_editing) return;
    final canDelete = widget.isOwn || widget.canManageMessages;
    final canReport = !widget.isOwn && widget.spaceId != null;
    final entries = <AccordMenuEntry>[
      AccordMenuEntry(
        label: 'Add reaction',
        icon: Icons.add_reaction_outlined,
        onSelected: () => _openReactionPicker(message.id),
      ),
      AccordMenuEntry(
        label: 'Reply',
        icon: Icons.reply,
        onSelected: widget.onReply,
      ),
      AccordMenuEntry(
        label: 'Thread',
        icon: Icons.forum_outlined,
        onSelected: () => _openThread(message),
      ),
      ...buildMessageActionEntries(
        content: message.content,
        canEdit: widget.isOwn,
        canDelete: canDelete,
        onEdit: () => _startEdit(message),
        onDelete: () => _delete(message.id),
        // Pin sits between Edit and Delete in this menu; it's site-specific
        // (the thread view has no pinning) so it slots in via [beforeDelete].
        beforeDelete: [
          if (widget.canManageMessages)
            AccordMenuEntry(
              label: message.pinned ? 'Unpin' : 'Pin',
              icon: message.pinned ? Icons.push_pin_outlined : Icons.push_pin,
              onSelected: () =>
                  _togglePin(message.id, pinned: message.pinned),
            ),
        ],
      ),
      if (canReport)
        AccordMenuEntry(
          label: 'Report',
          icon: Icons.flag_outlined,
          onSelected: () => _report(message.id),
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

  Widget _buildThreadChip(
    AccordMessage message,
    ThemeData theme,
    BonfireThemeExtension colors,
  ) {
    final count = message.replyCount;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _openThread(message),
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
    AccordMessage message,
    ThemeData theme,
    BonfireThemeExtension colors,
    String? cdnUrl,
  ) {
    final messageId = message.id;
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
          for (final reaction in message.reactions!)
            _ReactionPill(
              reaction: reaction,
              imageUrl: _reactionEmojiUrl(reaction, customEmoji, cdnUrl),
              onTap: () => _toggleReaction(
                messageId,
                reaction.emoji['name']?.toString() ?? '',
                emojiId: reaction.emoji['id']?.toString(),
              ),
              onShowReactors: () => _showReactors(messageId, reaction),
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
  Widget _buildReplyPreview(
    AccordMessage message,
    BonfireThemeExtension colors,
  ) {
    final theme = Theme.of(context);
    final messages = ref.read(
      accordMessagesControllerProvider(widget.channelId),
    );
    final referenced = messages?.firstWhereOrNull(
      (m) => m.id == message.replyTo,
    );
    String name = 'Unknown';
    String preview = '';
    if (referenced != null) {
      // Same resolution order as the row header: member nickname → on-demand
      // user cache → "Unknown" while the fetch lands. Never the raw snowflake.
      final authorId = referenced.authorId;
      final member = widget.spaceId == null
          ? null
          : ref.watch(
              accordMembersControllerProvider(
                widget.spaceId!,
              ).select((m) => m?[authorId]),
            );
      final user = ref.watch(
        accordUsersControllerProvider.select((u) => u[authorId]),
      );
      name = accordAuthorNameOf(
        authorId,
        member: member,
        user: user,
        ensure: ref.read(accordUsersControllerProvider.notifier).ensure,
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
    switch (_previewOf(attachment)) {
      case AttachmentPreview.image:
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
      case AttachmentPreview.video:
        return InlineVideoPlayer(
          url: url,
          filename: attachment.filename,
          width: _asDouble(attachment.width),
          height: _asDouble(attachment.height),
        );
      case AttachmentPreview.audio:
        return InlineAudioPlayer(url: url, filename: attachment.filename);
      case AttachmentPreview.none:
        return Text(
          '📎 ${attachment.filename}',
          style: theme.textTheme.bodyMedium,
        );
    }
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
