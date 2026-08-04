part of 'accord_direct_messages.dart';

class _DmListTab extends ConsumerStatefulWidget {
  const _DmListTab({required this.selfId, required this.onOpen});

  final String? selfId;
  final ValueChanged<AccordChannel> onOpen;

  @override
  ConsumerState<_DmListTab> createState() => _DmListTabState();
}

class _DmListTabState extends ConsumerState<_DmListTab> {
  @override
  void initState() {
    super.initState();
    _load();
  }

  AccordClient? get _client => ref.accordClient;

  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    final result = await client.users.listChannels();
    if (!mounted) return;
    final data = result.data;
    ref.read(dmChannelsControllerProvider.notifier).setChannels(
          data is List ? data.whereType<AccordChannel>().toList() : const [],
        );
  }

  Future<void> _createGroup() async {
    final channel = await showDialog<AccordChannel>(
      context: context,
      builder: (_) => const _CreateGroupDialog(),
    );
    if (channel == null || !mounted) return;
    // Surface the new group immediately; the gateway channel.create echo (and
    // the next _load) keep the cache authoritative.
    ref.read(dmChannelsControllerProvider.notifier).upsert(channel);
    widget.onOpen(channel);
  }

  /// Prompts for a remote user's qualified handle (`<id>@<domain>`) and opens a
  /// cross-server DM with them. The opened channel is reflected in the DM list
  /// (and surfaced) by [openAccordDirectMessage].
  Future<void> _messageRemoteUser() async {
    final handle = await showDialog<String>(
      context: context,
      builder: (_) => const _RemoteDmDialog(),
    );
    if (handle == null || !mounted) return;
    await openAccordDirectMessage(context, ref, handle);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final channels = ref.watch(dmChannelsControllerProvider);
    final cdnUrl = ref.watchCdnUrl();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _createGroup,
                icon: const Icon(Icons.group_add, size: 18),
                label: const Text('New group'),
              ),
              OutlinedButton.icon(
                onPressed: _messageRemoteUser,
                icon: const Icon(Icons.alternate_email, size: 18),
                label: const Text('Message remote user'),
              ),
            ],
          ),
        ),
        Expanded(
          child: channels == null
              ? const LoadingView()
              : channels.isEmpty
                  ? Center(
                      child: Text('No direct messages yet',
                          style: theme.textTheme.bodyMedium))
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: channels.length,
                      itemBuilder: (context, index) {
                        final channel = channels[index];
                        final title = _channelTitle(channel, widget.selfId);
                        final group = _isGroup(channel, widget.selfId);
                        final origin =
                            _dmRemoteOrigin(channel, widget.selfId);
                        final others = _others(channel, widget.selfId);
                        final other =
                            group || others.isEmpty ? null : others.first;
                        final avatarUrl = other == null
                            ? null
                            : accordAvatarUrl(other, cdnUrl);
                        return ListTile(
                          leading: group
                              ? CircleAvatar(
                                  backgroundColor: colors.darkGray,
                                  child: Icon(Icons.group,
                                      size: 18, color: colors.dirtyWhite),
                                )
                              : UserAvatar(title,
                                  imageUrl: avatarUrl, radius: 20),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                              if (origin != null) ...[
                                const SizedBox(width: 6),
                                RemoteOriginBadge(domain: origin),
                              ],
                            ],
                          ),
                          subtitle: group
                              ? Text(
                                  '${_others(channel, widget.selfId).length + 1} members',
                                  style: theme.textTheme.bodySmall)
                              : null,
                          onTap: () => widget.onOpen(channel),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _DmConversation extends ConsumerStatefulWidget {
  const _DmConversation({
    required this.channel,
    required this.selfId,
    required this.onBack,
  });

  final AccordChannel channel;
  final String? selfId;
  final VoidCallback onBack;

  @override
  ConsumerState<_DmConversation> createState() => _DmConversationState();
}

class _DmConversationState extends ConsumerState<_DmConversation> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  List<AccordMessage>? _messages;
  late AccordChannel _channel = widget.channel;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  AccordClient? get _client => ref.accordClient;

  bool get _isGroupChannel => _isGroup(_channel, widget.selfId);

  bool get _isOwner =>
      _channel.ownerId != null && _channel.ownerId == widget.selfId;

  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    final result =
        await client.messages.list(_channel.id, query: {'limit': 50});
    if (!mounted) return;
    final data = result.data;
    setState(() {
      _messages = data is List
          ? data.whereType<AccordMessage>().toList().reversed.toList()
          : <AccordMessage>[];
    });
  }

  /// Updates the local channel and mirrors it into the shared DM cache so the
  /// list behind this conversation reflects the change too.
  void _setChannel(AccordChannel channel) {
    setState(() => _channel = channel);
    ref.read(dmChannelsControllerProvider.notifier).upsert(channel);
  }

  /// Refetches the channel so the recipient list reflects add/remove changes.
  Future<void> _refreshChannel() async {
    final client = _client;
    if (client == null) return;
    final result = await client.channels.fetch(_channel.id);
    if (!mounted) return;
    final data = result.data;
    if (result.ok && data is AccordChannel) {
      _setChannel(data);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    final client = _client;
    if (client == null) return;
    // Clear up front rather than after the round-trip. The field is never
    // disabled (that would drop focus and the mobile keyboard for the whole
    // send), so it has to be free for the next message straight away; the text
    // comes back if the send fails.
    _input.clear();
    setState(() => _sending = true);
    final result =
        await client.messages.create(_channel.id, {'content': text});
    if (!mounted) return;
    final message = result.data;
    if (result.ok && message is AccordMessage) {
      setState(() {
        _sending = false;
        _messages = [...?_messages, message];
      });
      return;
    }
    // Hand the message back so it can be retried instead of retyped.
    setState(() => _sending = false);
    restoreFailedSend(_input, text);
    _snack('Failed to send message');
  }

  Future<void> _addMember() async {
    final user = await showDialog<AccordUser>(
      context: context,
      builder: (_) => _PickUserDialog(
        title: 'Add to group',
        excludeIds: {
          if (widget.selfId != null) widget.selfId!,
          ..._others(_channel, widget.selfId).map((u) => u.id),
        },
      ),
    );
    if (user == null) return;
    final client = _client;
    if (client == null) return;
    final result = await client.channels.addRecipient(_channel.id, user.id);
    if (!mounted) return;
    if (result.ok) {
      await _refreshChannel();
    } else {
      _snack('Failed to add member');
    }
  }

  Future<void> _removeMember(AccordUser user) async {
    final client = _client;
    if (client == null) return;
    final ok = await _confirm(
        'Remove member', 'Remove ${_userName(user)} from this group?', 'Remove');
    if (ok != true) return;
    final result =
        await client.channels.removeRecipient(_channel.id, user.id);
    if (!mounted) return;
    if (result.ok) {
      await _refreshChannel();
    } else {
      _snack('Failed to remove member');
    }
  }

  Future<void> _rename() async {
    final name = await showTextPromptDialog(
      context,
      title: 'Rename group',
      label: 'Group name',
      initial: _channel.name ?? '',
    );
    if (name == null) return;
    final client = _client;
    if (client == null) return;
    final result =
        await client.channels.update(_channel.id, {'name': name.trim()});
    if (!mounted) return;
    final data = result.data;
    if (result.ok && data is AccordChannel) {
      _setChannel(data);
    } else if (result.ok) {
      await _refreshChannel();
    } else {
      _snack('Failed to rename group');
    }
  }

  Future<void> _leave() async {
    final selfId = widget.selfId;
    final client = _client;
    if (client == null || selfId == null) return;
    final ok = await _confirm(
        'Leave group', 'Leave this group? You can be re-added later.', 'Leave');
    if (ok != true) return;
    final result = await client.channels.removeRecipient(_channel.id, selfId);
    if (!mounted) return;
    if (result.ok) {
      ref.read(dmChannelsControllerProvider.notifier).remove(_channel.id);
      widget.onBack();
    } else {
      _snack('Failed to leave group');
    }
  }

  void _snack(String message) {
    showInfoSnack(context, message);
  }

  Future<bool?> _confirm(String title, String message, String action) {
    return showConfirmDialog(
      context,
      title: title,
      message: message,
      confirmLabel: action,
    );
  }

  /// Places an outgoing DM call: rings the other participant(s) and opens the
  /// full-screen call view. The callee gets a `call.ring` and can accept/decline.
  Future<void> _startCall({required bool video}) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    await ref
        .read(callControllerProvider.notifier)
        .startCall(_channel, video: video);
    if (!mounted) return;
    // Bail if the underlying voice join failed (an error is surfaced elsewhere).
    if (ref.read(voiceControllerProvider).channelId != _channel.id) return;
    await showFullScreenVoice(
      navigator.context,
      channelId: _channel.id,
      spaceId: null,
      channelName: _channelTitle(_channel, widget.selfId),
    );
  }

  void _showMembers() {
    showDialog<void>(
      context: context,
      builder: (_) => _GroupMembersDialog(
        members: _others(_channel, widget.selfId),
        canRemove: _isOwner,
        onRemove: (u) {
          Navigator.of(context).pop();
          _removeMember(u);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    // Keep the open conversation in sync with gateway-driven channel updates
    // (remote rename / recipient add/remove) the DM cache receives.
    ref.listen<List<AccordChannel>?>(dmChannelsControllerProvider,
        (previous, next) {
      if (next == null) return;
      AccordChannel? updated;
      for (final c in next) {
        if (c.id == _channel.id) {
          updated = c;
          break;
        }
      }
      if (updated != null && !identical(updated, _channel)) {
        setState(() => _channel = updated!);
      }
    });
    final messages = _messages;
    final group = _isGroupChannel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Back',
                onPressed: widget.onBack,
                icon: Icon(Icons.arrow_back, size: 20, color: colors.dirtyWhite),
              ),
              if (group)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: CircleAvatar(
                    radius: 14,
                    backgroundColor: colors.darkGray,
                    child:
                        Icon(Icons.group, size: 16, color: colors.dirtyWhite),
                  ),
                ),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(_channelTitle(_channel, widget.selfId),
                          style: theme.textTheme.titleSmall,
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (_dmRemoteOrigin(_channel, widget.selfId) != null) ...[
                      const SizedBox(width: 6),
                      RemoteOriginBadge(
                          domain: _dmRemoteOrigin(_channel, widget.selfId)),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Start voice call',
                onPressed: () => _startCall(video: false),
                icon: Icon(Icons.call, size: 20, color: colors.dirtyWhite),
              ),
              IconButton(
                tooltip: 'Start video call',
                onPressed: () => _startCall(video: true),
                icon: Icon(Icons.videocam, size: 20, color: colors.dirtyWhite),
              ),
              if (group)
                PopupMenuButton<String>(
                  tooltip: 'Group options',
                  icon: Icon(Icons.more_vert, size: 20, color: colors.gray),
                  onSelected: (value) {
                    switch (value) {
                      case 'members':
                        _showMembers();
                      case 'add':
                        _addMember();
                      case 'rename':
                        _rename();
                      case 'leave':
                        _leave();
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                        value: 'members', child: Text('View members')),
                    const PopupMenuItem(
                        value: 'add', child: Text('Add member')),
                    const PopupMenuItem(
                        value: 'rename', child: Text('Rename group')),
                    PopupMenuItem(
                      value: 'leave',
                      child:
                          Text('Leave group', style: TextStyle(color: colors.red)),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: messages == null
              ? const LoadingView()
              : messages.isEmpty
                  ? Center(
                      child: Text('No messages yet',
                          style: theme.textTheme.bodySmall))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final m = messages[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: AccordMessageContent(content: m.content),
                        );
                      },
                    ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  focusNode: _inputFocus,
                  // Never disabled while sending: a disabled TextField gives up
                  // focus (and the mobile keyboard) for the whole round-trip.
                  // The send button and the guard in _send() stop double-sends.
                  minLines: 1,
                  maxLines: 4,
                  // A multiline field defaults to TextInputAction.newline, which
                  // swallows Enter instead of submitting; match the main
                  // composer so Enter sends.
                  textInputAction: TextInputAction.send,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Message',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) {
                    // EditableText unfocuses on a `send` action just before
                    // onSubmitted runs; the field is enabled, so asking for
                    // focus straight back lands in the same frame.
                    _inputFocus.requestFocus();
                    _send();
                  },
                ),
              ),
              IconButton(
                onPressed: _sending ? null : _send,
                icon: Icon(Icons.send, size: 20, color: colors.dirtyWhite),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Prompts for a remote user's qualified handle (`<id>@<domain>`) to start a
/// cross-server DM. Pops the validated, trimmed handle on submit, or null on
/// cancel. Identity discovery is out of scope — the user supplies the handle
/// (e.g. shared out-of-band or copied from a remote profile).
class _RemoteDmDialog extends StatefulWidget {
  const _RemoteDmDialog();

  @override
  State<_RemoteDmDialog> createState() => _RemoteDmDialogState();
}

class _RemoteDmDialogState extends State<_RemoteDmDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// A handle is valid when it is a qualified remote id: a non-empty local part
  /// and a home domain (`<id>@<domain>`). Local (bare) ids are rejected — this
  /// flow is specifically for users on another server.
  void _submit() {
    final value = _controller.text.trim();
    if (!isValidRemoteHandle(value)) {
      setState(
          () => _error = 'Enter a qualified handle, e.g. 123@server.example');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Message a remote user'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter the user\'s qualified handle on their home server.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              isDense: true,
              hintText: '123@server.example',
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Message'),
        ),
      ],
    );
  }
}
