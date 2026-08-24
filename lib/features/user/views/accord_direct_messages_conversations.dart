part of 'accord_direct_messages.dart';

class _DmListTab extends ConsumerStatefulWidget {
  const _DmListTab({required this.selfId, required this.onOpen});

  final String? selfId;
  final ValueChanged<AccordChannel> onOpen;

  @override
  ConsumerState<_DmListTab> createState() => _DmListTabState();
}

class _DmListTabState extends ConsumerState<_DmListTab> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  AccordClient? get _client => ref.accordClient;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final client = _client;
    final serverKey = ref.readActiveServerKey();
    if (client == null || serverKey == null) return;
    final result = await client.users.listChannels();
    if (!mounted || ref.readActiveServerKey() != serverKey) return;
    final data = result.data;
    final channels = data is List
        ? data.whereType<AccordChannel>().toList()
        : <AccordChannel>[];
    final controller = ref.read(
      dmChannelsControllerProvider(serverKey).notifier,
    );
    controller.setChannels(channels);
    await Future.wait([
      for (final channel in channels)
        client.messages.list(channel.id, query: {'limit': 1}).then((result) {
          if (!mounted || ref.readActiveServerKey() != serverKey) return;
          final messages = result.data;
          if (result.ok && messages is List) {
            AccordMessage? latest;
            for (final message in messages.whereType<AccordMessage>()) {
              latest = message;
              break;
            }
            if (latest != null) controller.setPreview(channel.id, latest);
          }
        }),
    ]);
  }

  Future<void> _createGroup() async {
    final serverKey = ref.readActiveServerKey();
    final channel = await showDialog<AccordChannel>(
      context: context,
      builder: (_) => const _CreateGroupDialog(),
    );
    if (channel == null ||
        !mounted ||
        serverKey == null ||
        ref.readActiveServerKey() != serverKey) {
      return;
    }
    // Surface the new group immediately; the gateway channel.create echo (and
    // the next _load) keep the cache authoritative.
    ref.read(dmChannelsControllerProvider(serverKey).notifier).upsert(channel);
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

  Future<void> _closeConversation(AccordChannel channel) async {
    final group = _isGroup(channel, widget.selfId);
    final confirmed = await showConfirmDialog(
      context,
      title: group ? 'Leave group' : 'Close direct message',
      message: group
          ? 'Leave ${_channelTitle(channel, widget.selfId)}? You can be re-added later.'
          : 'Remove this conversation from your direct-message list? Its history is retained if you message this user again.',
      confirmLabel: group ? 'Leave' : 'Close',
      danger: true,
    );
    if (confirmed != true || !mounted) return;
    final client = _client;
    final serverKey = ref.readActiveServerKey();
    if (client == null || serverKey == null) return;
    final result = await client.channels.delete(channel.id);
    if (!mounted || ref.readActiveServerKey() != serverKey) return;
    if (!result.ok) {
      _snackDmError(context, result.error, 'Failed to close conversation');
      return;
    }
    ref
        .read(dmChannelsControllerProvider(serverKey).notifier)
        .remove(channel.id);
    ref
        .read(readStateControllerProvider(serverKey).notifier)
        .markRead(channel.id);
  }

  void _showConversationMenu(AccordChannel channel, Offset? position) {
    final group = _isGroup(channel, widget.selfId);
    final others = _others(channel, widget.selfId);
    final user = !group && others.isNotEmpty ? others.first : null;
    final closeEntry = AccordMenuEntry(
      label: group ? 'Leave group' : 'Close direct message',
      icon: group ? Icons.logout : Icons.close,
      destructive: true,
      onSelected: () => _closeConversation(channel),
    );
    if (user != null) {
      showAccordDmUserContextMenu(
        context,
        ref,
        user,
        globalPosition: position,
        currentDmUserId: user.id,
        extraEntries: [const AccordMenuEntry.divider(), closeEntry],
      );
      return;
    }
    showAccordContextMenu(
      context,
      entries: [closeEntry],
      globalPosition: position,
      title: _channelTitle(channel, widget.selfId),
      titleIcon: Icons.group_outlined,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final serverKey = ref.watchActiveServerKey() ?? '';
    final channels = ref.watch(dmChannelsControllerProvider(serverKey));
    final previews = ref.read(dmChannelsControllerProvider(serverKey).notifier);
    final cdnUrl = ref.watchCdnUrl();
    final missed = ref.watch(missedCallsControllerProvider);
    final readState = ref.watch(readStateControllerProvider(serverKey));
    final channelLevels = ref.watch(
      settingsControllerProvider.select(
        (settings) => settings.channelNotificationsFor(serverKey),
      ),
    );
    final query = _search.text.trim().toLowerCase();
    final filtered = channels
        ?.where(
          (channel) =>
              query.isEmpty ||
              _channelTitle(
                channel,
                widget.selfId,
              ).toLowerCase().contains(query),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Column(
            children: [
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 20),
                  hintText: 'Search conversations',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
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
            ],
          ),
        ),
        Expanded(
          child: channels == null
              ? const LoadingView()
              : filtered!.isEmpty
              ? Center(
                  child: Text(
                    query.isEmpty
                        ? 'No direct messages yet'
                        : 'No matching conversations',
                    style: theme.textTheme.bodyMedium,
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final channel = filtered[index];
                    final title = _channelTitle(channel, widget.selfId);
                    final group = _isGroup(channel, widget.selfId);
                    final origin = _dmRemoteOrigin(channel, widget.selfId);
                    final others = _others(channel, widget.selfId);
                    final other = group || others.isEmpty ? null : others.first;
                    final avatarUrl = other == null
                        ? null
                        : accordAvatarUrl(other, cdnUrl);
                    final missedCall = missed[channel.id];
                    final unread = readState.isUnreadVisible(
                      channel.id,
                      channelLevels: channelLevels,
                    );
                    final mentions = readState.visibleMentionCount(
                      channel.id,
                      channelLevels: channelLevels,
                    );
                    final preview = previews.previewFor(channel.id);
                    final tile = ListTile(
                      tileColor: unread
                          ? colors.primary.withValues(alpha: 0.08)
                          : null,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      leading: group
                          ? CircleAvatar(
                              backgroundColor: colors.darkGray,
                              child: Icon(
                                Icons.group,
                                size: 18,
                                color: colors.dirtyWhite,
                              ),
                            )
                          : UserAvatar(title, imageUrl: avatarUrl, radius: 20),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: unread
                                  ? const TextStyle(fontWeight: FontWeight.w700)
                                  : null,
                            ),
                          ),
                          if (origin != null) ...[
                            const SizedBox(width: 6),
                            RemoteOriginBadge(domain: origin),
                          ],
                        ],
                      ),
                      subtitle: missedCall != null
                          ? _MissedCallLabel(missed: missedCall)
                          : preview != null
                          ? Text(
                              preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            )
                          : group
                          ? Text(
                              '${_others(channel, widget.selfId).length + 1} members',
                              style: theme.textTheme.bodySmall,
                            )
                          : null,
                      trailing: mentions > 0
                          ? Badge(label: Text('$mentions'))
                          : unread || missedCall != null
                          ? Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: missedCall != null
                                    ? colors.red
                                    : colors.primary,
                                shape: BoxShape.circle,
                              ),
                            )
                          : null,
                      onTap: () => widget.onOpen(channel),
                    );
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onLongPressStart: (details) => _showConversationMenu(
                        channel,
                        details.globalPosition,
                      ),
                      onSecondaryTapUp: (details) => _showConversationMenu(
                        channel,
                        details.globalPosition,
                      ),
                      child: tile,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// The "Missed call" line under a DM row: an unanswered incoming call the user
/// hasn't opened the conversation for yet. Cleared by opening the conversation.
class _MissedCallLabel extends StatelessWidget {
  const _MissedCallLabel({required this.missed});

  final MissedCall missed;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: colors.red,
      fontWeight: FontWeight.w600,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          missed.video ? Icons.missed_video_call : Icons.call_missed,
          size: 14,
          color: colors.red,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            missed.label,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
  late AccordChannel _channel = widget.channel;
  late final String _serverKey = ref.readActiveServerKey() ?? '';
  ServerChannelKey? _previousVisibleChannel;

  @override
  void initState() {
    super.initState();
    _previousVisibleChannel = accordVisibleChannel;
    // Opening the conversation is the acknowledgement: drop any missed-call
    // indicator for it. Deferred a frame — `initState` runs during a build, and
    // Riverpod forbids mutating a provider from inside one.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final user in _channel.recipients ?? const <AccordUser>[]) {
        ref
            .read(accordUsersControllerProvider(_serverKey).notifier)
            .upsert(user);
      }
      accordVisibleChannel = (serverKey: _serverKey, channelId: _channel.id);
      markChannelRead(
        ref,
        _channel.id,
        serverKey: _serverKey,
        fallbackMessageId: _channel.lastMessageId,
      );
      ref.read(missedCallsControllerProvider.notifier).clear(_channel.id);
    });
  }

  @override
  void dispose() {
    final visible = accordVisibleChannel;
    if (visible?.serverKey == _serverKey && visible?.channelId == _channel.id) {
      accordVisibleChannel = _previousVisibleChannel;
    }
    super.dispose();
  }

  AccordClient? get _client => ref.accordClient;

  bool get _isGroupChannel => _isGroup(_channel, widget.selfId);

  bool get _isOwner =>
      _channel.ownerId != null && _channel.ownerId == widget.selfId;

  /// Updates the local channel and mirrors it into the shared DM cache so the
  /// list behind this conversation reflects the change too.
  void _setChannel(AccordChannel channel) {
    setState(() => _channel = channel);
    ref
        .read(
          dmChannelsControllerProvider(
            ref.readActiveServerKey() ?? '',
          ).notifier,
        )
        .upsert(channel);
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
      'Remove member',
      'Remove ${_userName(user)} from this group?',
      'Remove',
    );
    if (ok != true) return;
    final result = await client.channels.removeRecipient(_channel.id, user.id);
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
    final result = await client.channels.update(_channel.id, {
      'name': name.trim(),
    });
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
      'Leave group',
      'Leave this group? You can be re-added later.',
      'Leave',
    );
    if (ok != true) return;
    final result = await client.channels.removeRecipient(_channel.id, selfId);
    if (!mounted) return;
    if (result.ok) {
      ref
          .read(
            dmChannelsControllerProvider(
              ref.readActiveServerKey() ?? '',
            ).notifier,
          )
          .remove(_channel.id);
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
    final colors = BonfireThemeExtension.of(context);
    // Keep the open conversation in sync with gateway-driven channel updates
    // (remote rename / recipient add/remove) the DM cache receives.
    ref.listen<List<AccordChannel>?>(
      dmChannelsControllerProvider(ref.readActiveServerKey() ?? ''),
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
      },
    );
    ref.listen<List<AccordMessage>?>(
      accordMessagesControllerProvider(_serverKey, _channel.id),
      (previous, next) {
        if (next == null || next.isEmpty) return;
        markChannelRead(
          ref,
          _channel.id,
          serverKey: _serverKey,
          fallbackMessageId: next.last.id,
        );
      },
    );
    // The home route remains mounted beneath this dialog and may rebuild while
    // it is open. Reassert the modal conversation as the visible channel so its
    // incoming messages do not produce unread badges/notifications.
    accordVisibleChannel = (serverKey: _serverKey, channelId: _channel.id);
    final group = _isGroupChannel;
    final others = _others(_channel, widget.selfId);
    final directUser = group || others.isEmpty ? null : others.first;
    final title = _channelTitle(_channel, widget.selfId);
    final origin = _dmRemoteOrigin(_channel, widget.selfId);
    return MessagePane(
      channel: _channel,
      channelId: _channel.id,
      spaceId: null,
      canManageMessagesOverride: true,
      headerLeading: Row(
        mainAxisSize: MainAxisSize.min,
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
                child: Icon(Icons.group, size: 16, color: colors.dirtyWhite),
              ),
            )
          else if (directUser != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _DmUserGesture(
                user: directUser,
                onTap: () => _showUserProfile(directUser),
                onMenu: (position) => _showUserMenu(directUser, position),
                child: UserAvatar(
                  title,
                  imageUrl: accordAvatarUrl(directUser, ref.watchCdnUrl()),
                  radius: 14,
                ),
              ),
            ),
        ],
      ),
      headerTitle: _DmHeaderTitle(
        title: title,
        origin: origin,
        onTap: directUser == null ? null : () => _showUserProfile(directUser),
        onMenu: directUser == null
            ? null
            : (position) => _showUserMenu(directUser, position),
      ),
      headerActions: [
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
        if (group) _groupOptions(colors),
      ],
      onUserTap: _showUserProfile,
      onUserContextMenu: _showUserMenu,
    );
  }

  void _showUserProfile(AccordUser user) {
    showAccordUserProfile(context, user, cdnUrl: ref.readCdnUrl());
  }

  void _showUserMenu(AccordUser user, [Offset? position]) {
    final others = _others(_channel, widget.selfId);
    showAccordDmUserContextMenu(
      context,
      ref,
      user,
      globalPosition: position,
      currentDmUserId: others.length == 1 ? others.first.id : null,
    );
  }

  Widget _groupOptions(BonfireThemeExtension colors) => PopupMenuButton<String>(
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
      const PopupMenuItem(value: 'members', child: Text('View members')),
      const PopupMenuItem(value: 'add', child: Text('Add member')),
      const PopupMenuItem(value: 'rename', child: Text('Rename group')),
      PopupMenuItem(
        value: 'leave',
        child: Text('Leave group', style: TextStyle(color: colors.red)),
      ),
    ],
  );
}

class _DmHeaderTitle extends StatelessWidget {
  const _DmHeaderTitle({
    required this.title,
    required this.origin,
    required this.onTap,
    required this.onMenu,
  });

  final String title;
  final String? origin;
  final VoidCallback? onTap;
  final ValueChanged<Offset?>? onMenu;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        Flexible(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (origin != null) ...[
          const SizedBox(width: 6),
          RemoteOriginBadge(domain: origin),
        ],
      ],
    );
    if (onTap == null && onMenu == null) return row;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPressStart: onMenu == null
            ? null
            : (details) => onMenu!(details.globalPosition),
        onSecondaryTapUp: onMenu == null
            ? null
            : (details) => onMenu!(details.globalPosition),
        child: row,
      ),
    );
  }
}

class _DmUserGesture extends StatelessWidget {
  const _DmUserGesture({
    required this.user,
    required this.onTap,
    required this.onMenu,
    required this.child,
  });

  final AccordUser user;
  final VoidCallback onTap;
  final ValueChanged<Offset?> onMenu;
  final Widget child;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: onTap,
      onLongPressStart: (details) => onMenu(details.globalPosition),
      onSecondaryTapUp: (details) => onMenu(details.globalPosition),
      child: child,
    ),
  );
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
        () => _error = 'Enter a qualified handle, e.g. 123@server.example',
      );
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
        FilledButton(onPressed: _submit, child: const Text('Message')),
      ],
    );
  }
}
