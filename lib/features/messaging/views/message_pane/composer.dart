part of 'message_pane.dart';

class _Composer extends ConsumerStatefulWidget {
  const _Composer({
    required this.channelId,
    this.channelName,
    this.spaceId,
    this.replyingTo,
    this.replyName,
    this.onCancelReply,
  });

  final String channelId;
  final String? channelName;
  final String? spaceId;
  final AccordMessage? replyingTo;
  final String? replyName;
  final VoidCallback? onCancelReply;

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _sending = false;

  /// Files the user has attached but not yet sent.
  final List<PendingAttachment> _attachments = [];

  /// True while a file drag is hovering the composer, which swaps the hint for
  /// a drop prompt and outlines the box.
  bool _dragging = false;

  /// Why the last attach or send didn't work, shown above the composer.
  /// Cleared when the user attaches again or retries the send.
  String? _error;

  /// The server's typing indicator lasts ~10s, so we re-trigger at most once
  /// every 8s while the user keeps typing rather than on every keystroke.
  DateTime? _lastTypingSent;
  static const _typingInterval = Duration(seconds: 8);

  /// Mention-popup state. `_mentionQuery == null` means the popup is hidden;
  /// otherwise it's the lowercase text after the active `@`, and
  /// `[_mentionStart, _mentionEnd)` is the range in `_controller.text` that
  /// the picked handle replaces (covers the `@` and the query).
  String? _mentionQuery;
  int _mentionStart = -1;
  int _mentionEnd = -1;

  /// Captured once so `dispose()` can persist the draft without touching `ref`,
  /// which Riverpod tears down before `dispose()` runs. Safe because
  /// `SettingsController` is `keepAlive`, so this notifier outlives the widget.
  late final SettingsController _settings;

  /// Text pastes longer than this prompt to send as a `.txt` attachment.
  static const _largePasteThreshold = 2000;

  @override
  void initState() {
    super.initState();
    _settings = ref.read(settingsControllerProvider.notifier);
    _controller.text = ref
        .read(settingsControllerProvider)
        .draftFor(widget.channelId);
    // Intercept Ctrl/Cmd+V to support pasting images and large text (the
    // EditableText's own paste only handles inline text).
    _focusNode.onKeyEvent = _onComposerKey;
  }

  KeyEventResult _onComposerKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final mods = HardwareKeyboard.instance;
    final isPaste =
        (mods.isControlPressed || mods.isMetaPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyV;
    if (!isPaste) return KeyEventResult.ignored;
    // Consume and handle the paste ourselves (image / large-text aware).
    _handlePaste();
    return KeyEventResult.handled;
  }

  /// Handles a clipboard paste: an image becomes a pending attachment; very
  /// large text prompts to attach it as a `.txt` file; otherwise the text is
  /// inserted inline. Ports the reference composer's paste handling.
  Future<void> _handlePaste() async {
    Uint8List? image;
    try {
      image = await Pasteboard.image;
    } catch (_) {
      image = null;
    }
    if (!mounted) return;
    if (image != null && image.isNotEmpty) {
      final bytes = image;
      // The clipboard image isn't necessarily a PNG (it used to be named one
      // unconditionally); sniff the bytes so the name matches the content.
      _addFiles([
        PendingAttachment.fromBytes(
          name: pastedImageFilename(bytes),
          bytes: bytes,
        ),
      ]);
      return;
    }

    String text = '';
    try {
      text = await Pasteboard.text ?? '';
    } catch (_) {
      text = '';
    }
    if (!mounted || text.isEmpty) return;

    if (text.length > _largePasteThreshold) {
      final asFile = await _confirmLargePaste(text.length);
      if (!mounted || asFile == null) return;
      if (asFile) {
        final bytes = Uint8List.fromList(utf8.encode(text));
        _addFiles([
          PendingAttachment.fromBytes(name: 'message.txt', bytes: bytes),
        ]);
        return;
      }
    }
    _insertAtCursor(text);
  }

  /// Asks whether a large paste should become a `.txt` attachment. Returns true
  /// (file), false (inline), or null (cancelled).
  Future<bool?> _confirmLargePaste(int length) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paste large text'),
        content: Text(
          "That's a lot of text ($length characters). Attach it as a .txt "
          'file instead of pasting inline?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Paste inline'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Attach as file'),
          ),
        ],
      ),
    );
  }

  @override
  void didUpdateWidget(_Composer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channelId != widget.channelId) {
      // Channel switched within the same composer instance: persist the
      // outgoing channel's draft and restore the incoming channel's.
      _saveDraft(oldWidget.channelId, _controller.text);
      _controller.text = ref
          .read(settingsControllerProvider)
          .draftFor(widget.channelId);
      _lastTypingSent = null;
    }
  }

  /// Persists [text] as the draft for [channelId] (mirrors the reference
  /// client's `Config.set_draft_text`).
  void _saveDraft(String channelId, String text) {
    _settings.setDraft(channelId, text);
  }

  @override
  void dispose() {
    _saveDraft(widget.channelId, _controller.text);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _updateMentionState(value);
    if (value.trim().isEmpty) return;
    final now = DateTime.now();
    if (_lastTypingSent != null &&
        now.difference(_lastTypingSent!) < _typingInterval) {
      return;
    }
    _lastTypingSent = now;
    final client = ref.read(
      accordAuthProvider.select(
        (s) => s is AccordAuthLoggedIn ? s.client : null,
      ),
    );
    client?.messages.typing(widget.channelId);
  }

  /// Decides whether an `@` autocomplete is in progress and updates the
  /// popup state accordingly. Mirrors the reference composer's
  /// `_find_mention_trigger`: scan backwards from the cursor to the nearest
  /// `@` that's at line start or follows a non-word char; everything between
  /// it and the cursor is the query. A space (or no `@` before whitespace)
  /// dismisses the popup. The popup itself is only built when `_mentionQuery`
  /// is non-null AND there are candidates to show.
  void _updateMentionState(String text) {
    final selection = _controller.value.selection;
    if (!selection.isValid ||
        !selection.isCollapsed ||
        widget.spaceId == null) {
      _clearMentionState();
      return;
    }
    final caret = selection.baseOffset;
    var i = caret - 1;
    while (i >= 0) {
      final ch = text[i];
      if (ch == '@') {
        if (i > 0 && _isMentionWordChar(text[i - 1])) {
          _clearMentionState();
          return;
        }
        final query = text.substring(i + 1, caret).toLowerCase();
        setState(() {
          _mentionQuery = query;
          _mentionStart = i;
          _mentionEnd = caret;
        });
        return;
      }
      if (ch == ' ' || ch == '\t' || ch == '\n') {
        _clearMentionState();
        return;
      }
      i--;
    }
    _clearMentionState();
  }

  void _clearMentionState() {
    if (_mentionQuery == null) return;
    setState(() {
      _mentionQuery = null;
      _mentionStart = -1;
      _mentionEnd = -1;
    });
  }

  static bool _isMentionWordChar(String ch) {
    if (ch.isEmpty) return false;
    final code = ch.codeUnitAt(0);
    if (code >= 0x30 && code <= 0x39) return true; // 0-9
    if (code >= 0x41 && code <= 0x5A) return true; // A-Z
    if (code >= 0x61 && code <= 0x7A) return true; // a-z
    if (code == 0x5F) return true; // _
    return code > 0x7F; // non-ASCII letter-likes
  }

  /// Replaces the active `@query` range with `@handle ` and dismisses the
  /// popup. Mirrors the reference's `_on_mention_picked`.
  void _pickMention(String handle) {
    if (_mentionStart < 0 || _mentionEnd < 0) return;
    final text = _controller.text;
    if (_mentionEnd > text.length) return;
    final insert = '@$handle ';
    final next = text.replaceRange(_mentionStart, _mentionEnd, insert);
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: _mentionStart + insert.length),
    );
    _clearMentionState();
    _focusNode.requestFocus();
  }

  /// Opens the system file picker.
  ///
  /// No `allowedExtensions` filter: the Accord server enforces no type
  /// allow-list on message attachments (only size and count — see
  /// `AccordServerLimits`), so filtering here would make the client stricter
  /// than the protocol and hide legitimate files. Unrecognised types attach and
  /// upload; they simply don't preview inline.
  ///
  /// The picker call is guarded because it can throw rather than return null —
  /// Windows' legacy `GetOpenFileNameW` path in particular fails outright on a
  /// cloud placeholder or an over-MAX_PATH selection. Unguarded, that threw out
  /// of an unawaited `onPressed` callback and the user saw the attach button do
  /// nothing at all.
  Future<void> _pickFiles() async {
    final FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
      );
    } catch (e) {
      debugPrint('File picker failed: $e');
      if (mounted) {
        setState(() => _error = "Couldn't open the file picker: $e");
      }
      return;
    }
    if (result == null || !mounted) return;
    _addFiles([for (final file in result.files) PendingAttachment(file)]);
  }

  /// Attaches the files dragged onto the composer. Directories aren't
  /// attachable, and files are size-checked before being read so a dropped
  /// 4 GB video is rejected rather than pulled into memory first.
  Future<void> _onDrop(DropDoneDetails details) async {
    setState(() => _dragging = false);
    if (_sending) return;
    final picked = <PendingAttachment>[];
    final rejections = <String>[];
    final maxBytes = ref.read(serverLimitsControllerProvider).maxAttachmentBytes;
    for (final item in details.files) {
      // `DropItemDirectory` only comes back on macOS and web; Linux and Windows
      // share a handler that types every dropped path as a file, so the path
      // itself has to be checked or a folder reads as an unreadable file.
      if (item is DropItemDirectory || isDroppedDirectory(item.path)) {
        rejections.add(
          '${item.name} is a folder — drop the files inside it instead.',
        );
        continue;
      }
      // macOS sandbox: a file dragged in from outside the container is only
      // readable while its security-scoped bookmark is held open.
      final bookmark = item.extraAppleBookmark;
      final scoped = await _startScopedAccess(bookmark);
      try {
        final size = await item.length();
        if (size > maxBytes) {
          rejections.add(
            oversizeAttachmentMessage(item.name, size, maxBytes: maxBytes),
          );
          continue;
        }
        final bytes = await item.readAsBytes();
        picked.add(
          PendingAttachment.fromBytes(
            name: item.name,
            bytes: bytes,
            path: item.path.isEmpty ? null : item.path,
            // Drag-and-drop is the one path where the platform tells us what
            // the file is; prefer that over guessing from the extension.
            platformMimeType: item.mimeType,
          ),
        );
      } catch (_) {
        rejections.add(unreadableAttachmentMessage(item.name));
      } finally {
        if (scoped) await _stopScopedAccess(bookmark!);
      }
    }
    if (!mounted) return;
    _addFiles(picked, alsoRejected: rejections);
  }

  Future<bool> _startScopedAccess(Uint8List? bookmark) async {
    if (bookmark == null || bookmark.isEmpty) return false;
    try {
      return await DesktopDrop.instance.startAccessingSecurityScopedResource(
        bookmark: bookmark,
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> _stopScopedAccess(Uint8List bookmark) async {
    try {
      await DesktopDrop.instance.stopAccessingSecurityScopedResource(
        bookmark: bookmark,
      );
    } catch (_) {
      // Access lapses with the drop anyway; nothing useful to tell the user.
    }
  }

  /// Attaches every file in [files] that passes screening, and reports the ones
  /// that don't, along with any [alsoRejected] lines the caller screened out
  /// itself. Unreadable, oversize and over-the-count files used to be dropped
  /// in silence, which is indistinguishable from the attach button doing
  /// nothing.
  ///
  /// Screened against the connected server's own limits, not compiled-in ones.
  void _addFiles(
    Iterable<PendingAttachment> files, {
    List<String> alsoRejected = const [],
  }) {
    final limits = ref.read(serverLimitsControllerProvider);
    final screened = screenAttachments(
      files,
      maxBytes: limits.maxAttachmentBytes,
      maxCount: limits.maxAttachmentsPerMessage,
      alreadyAttached: _attachments.length,
    );
    final rejections = [...alsoRejected, ...screened.rejections];
    setState(() {
      _attachments.addAll(screened.accepted);
      _error = rejections.isEmpty ? null : rejections.join('\n');
    });
  }

  void _removeAttachment(PendingAttachment file) {
    setState(() => _attachments.remove(file));
  }

  Future<void> _pickEmoji() async {
    final pick = await showAccordEmojiPicker(context, spaceId: widget.spaceId);
    if (pick == null || !mounted) return;
    _insertAtCursor(pick.composerText);
  }

  /// Inserts [text] at the current cursor position (replacing any selection),
  /// keeping focus and placing the caret after the inserted text.
  void _insertAtCursor(String text) {
    final value = _controller.value;
    final selection = value.selection;
    final base = selection.isValid ? selection : null;
    final start = base?.start ?? value.text.length;
    final end = base?.end ?? value.text.length;
    final next = value.text.replaceRange(start, end, text);
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
    _focusNode.requestFocus();
  }

  Future<void> _send() async {
    // Emoticons convert on send, not on render, so the stored content holds the
    // real glyph for every other client (and for edit/copy here).
    final raw = _controller.text;
    final text =
        ref.read(settingsControllerProvider.select((s) => s.convertEmoticons))
        ? applyEmoticons(raw)
        : raw;
    if ((text.trim().isEmpty && _attachments.isEmpty) || _sending) return;

    final client = ref.read(
      accordAuthProvider.select(
        (s) => s is AccordAuthLoggedIn ? s.client : null,
      ),
    );
    if (client == null) return;

    final controller = ref.read(
      accordMessagesControllerProvider(widget.channelId).notifier,
    );
    final replyTo = widget.replyingTo?.id;
    final attachments = List<PendingAttachment>.of(_attachments);
    // Content type resolved when the file was attached (magic bytes → platform
    // MIME → extension table), not re-guessed from the extension here.
    final files = [for (final file in attachments) file.toUploadPart()];
    // Empty the composer up front rather than after the round-trip. The field
    // is never disabled (that would drop focus and the mobile keyboard for the
    // whole send), so it has to be free for the next message straight away;
    // everything cleared here comes back if the send fails.
    _controller.clear();
    _saveDraft(widget.channelId, '');
    _lastTypingSent = null;
    setState(() {
      _sending = true;
      _error = null;
      _attachments.clear();
      _mentionQuery = null;
    });

    // A throw here (rather than a returned error string) would otherwise escape
    // an unawaited callback: the composer would stay stuck with `_sending`
    // true — no spinner, no message, buttons dead — and the user's text and
    // attachments would be gone. Anything that goes wrong has to end up in
    // `_error` where it's on screen.
    final String? error;
    try {
      error = await controller.sendWithAttachments(
        client,
        text,
        files,
        replyTo: replyTo,
      );
    } catch (e) {
      debugPrint('Send failed: $e');
      if (mounted) {
        setState(() {
          _sending = false;
          _error = 'Failed to send: $e';
          _attachments.insertAll(0, attachments);
        });
        restoreFailedSend(_controller, text);
        _saveDraft(widget.channelId, _controller.text);
      }
      return;
    }
    if (!mounted) return;
    if (error == null) {
      setState(() => _sending = false);
      soundManager.play('message_sent');
      widget.onCancelReply?.call();
      return;
    }
    // Failed: hand the message back so it can be fixed and retried, keeping any
    // attachments ahead of ones added while this send was in flight.
    setState(() {
      _sending = false;
      _error = error;
      _attachments.insertAll(0, attachments);
    });
    restoreFailedSend(_controller, text);
    _saveDraft(widget.channelId, _controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    // Watched, not read: the limits arrive a round-trip after connect, and the
    // attach button's enabled state depends on the count limit.
    final limits = ref.watch(serverLimitsControllerProvider);
    final atAttachmentLimit =
        _attachments.length >= limits.maxAttachmentsPerMessage;
    final hint = _dragging
        ? 'Drop files to attach'
        : widget.channelName != null
        ? 'Message #${widget.channelName}'
        : 'Message';
    // A DropTarget keeps receiving drags even when covered, so it's disabled
    // while a dialog/sheet (emoji picker, lightbox, …) is on top of the pane.
    final onTop = ModalRoute.of(context)?.isCurrent ?? true;
    return DropTarget(
      enable: !_sending && onTop,
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: _onDrop,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: colors.darkGray,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _dragging ? colors.primary : Colors.transparent,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.replyingTo != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 4, 0),
                  child: Row(
                    children: [
                      Icon(Icons.reply, size: 14, color: colors.gray),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Replying to ${widget.replyName ?? 'message'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(
                            context,
                          ).textTheme.labelMedium!.copyWith(color: colors.gray),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cancel reply',
                        visualDensity: VisualDensity.compact,
                        onPressed: widget.onCancelReply,
                        icon: Icon(Icons.close, size: 14, color: colors.gray),
                      ),
                    ],
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 4, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: InlineError(_error!, centered: false)),
                      IconButton(
                        tooltip: 'Dismiss',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() => _error = null),
                        icon: Icon(Icons.close, size: 14, color: colors.gray),
                      ),
                    ],
                  ),
                ),
              if (_attachments.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final file in _attachments)
                        _AttachmentChip(
                          attachment: file,
                          onRemove: _sending
                              ? null
                              : () => _removeAttachment(file),
                        ),
                    ],
                  ),
                ),
              if (_mentionQuery != null && widget.spaceId != null)
                _MentionPopup(
                  spaceId: widget.spaceId!,
                  query: _mentionQuery!,
                  onPick: _pickMention,
                ),
              Row(
                children: [
                  IconButton(
                    tooltip: atAttachmentLimit
                        ? 'Attachment limit reached '
                            '(${limits.maxAttachmentsPerMessage} per message)'
                        : 'Attach files',
                    onPressed: _sending || atAttachmentLimit ? null : _pickFiles,
                    icon: Icon(
                      Icons.add_circle_outline,
                      size: 20,
                      color: atAttachmentLimit
                          ? colors.gray
                          : colors.dirtyWhite,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      // Deliberately never disabled while sending: a disabled
                      // TextField gives up focus (and the mobile keyboard) for
                      // the whole round-trip. The buttons below and the guard
                      // in _send() are what stop a double-send.
                      minLines: 1,
                      maxLines: 6,
                      textInputAction: TextInputAction.send,
                      onChanged: _onChanged,
                      onSubmitted: (_) {
                        // EditableText unfocuses on a `send` action just before
                        // onSubmitted runs; the field is enabled, so asking for
                        // focus straight back lands in the same frame.
                        _focusNode.requestFocus();
                        _send();
                      },
                      style: Theme.of(context).textTheme.bodyLarge,
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: hint,
                        hintStyle: Theme.of(
                          context,
                        ).textTheme.bodyLarge!.copyWith(color: colors.gray),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Emoji',
                    onPressed: _sending ? null : _pickEmoji,
                    icon: Icon(
                      Icons.emoji_emotions_outlined,
                      size: 20,
                      color: colors.dirtyWhite,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Send',
                    onPressed: _sending ? null : _send,
                    icon: Icon(Icons.send, size: 20, color: colors.dirtyWhite),
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

/// Compact "@" autocomplete popup rendered above the composer. Lists
/// members of [spaceId] (and mentionable roles) whose name starts with —
/// or contains — [query]; tapping inserts the handle into the composer via
/// [onPick]. Hidden automatically by the composer when [query] becomes
/// empty of matches.
class _MentionPopup extends ConsumerWidget {
  const _MentionPopup({
    required this.spaceId,
    required this.query,
    required this.onPick,
  });

  final String spaceId;
  final String query;
  final ValueChanged<String> onPick;

  static const int _maxResults = 6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final members = ref.watch(accordMembersControllerProvider(spaceId));
    final space = ref.watch(
      spacesControllerProvider.select(
        (s) => s?.firstWhereOrNull((sp) => sp.id == spaceId),
      ),
    );
    final roles = space?.roles ?? const <AccordRole>[];
    final entries = _filter(members, roles, query);
    if (entries.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.foreground, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in entries)
            InkWell(
              onTap: () => onPick(entry.handle),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    Icon(
                      entry.isRole ? Icons.label_outline : Icons.person,
                      size: 14,
                      color: colors.gray,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        entry.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      "@${entry.handle}",
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall!.copyWith(color: colors.gray),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Picks up to [_maxResults] candidates from members and mentionable roles
  /// whose handle/label matches [query] (case-insensitive). Prefix matches rank
  /// before substring matches; members rank before roles within each tier.
  List<_MentionEntry> _filter(
    Map<String, AccordMember>? members,
    List<AccordRole> roles,
    String query,
  ) {
    final q = query.toLowerCase();
    final prefix = <_MentionEntry>[];
    final contains = <_MentionEntry>[];
    void consider(_MentionEntry e) {
      final h = e.handle.toLowerCase();
      final l = e.label.toLowerCase();
      if (q.isEmpty || h.startsWith(q) || l.startsWith(q)) {
        prefix.add(e);
      } else if (h.contains(q) || l.contains(q)) {
        contains.add(e);
      }
    }

    if (members != null) {
      for (final m in members.values) {
        final user = m.user;
        final username = user?.username;
        if (username == null || username.isEmpty) continue;
        consider(
          _MentionEntry(
            handle: username,
            label: accordMemberName(m, fallback: username),
            isRole: false,
          ),
        );
      }
    }
    for (final r in roles) {
      if (!r.mentionable) continue;
      consider(_MentionEntry(handle: r.name, label: r.name, isRole: true));
    }
    final out = [...prefix, ...contains];
    if (out.length > _maxResults) return out.sublist(0, _maxResults);
    return out;
  }
}

class _MentionEntry {
  const _MentionEntry({
    required this.handle,
    required this.label,
    required this.isRole,
  });
  final String handle;
  final String label;
  final bool isRole;
}
