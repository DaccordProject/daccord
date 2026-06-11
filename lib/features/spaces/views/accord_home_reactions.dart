part of 'accord_home.dart';

/// Opens the full emoji picker to add a reaction to the message.
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
    this.imageUrl,
  });

  final AccordReaction reaction;
  final VoidCallback onTap;

  /// Long-press / right-click: reveal who reacted.
  final VoidCallback onShowReactors;

  /// Resolved image URL for a custom-emoji reaction; null for unicode.
  final String? imageUrl;

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
              if (id != null && imageUrl != null)
                CachedNetworkImage(
                  imageUrl: imageUrl!,
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
                    _ReactorTile(user: user, cdnUrl: cdnUrl),
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

class _ReactorTile extends StatelessWidget {
  const _ReactorTile({required this.user, required this.cdnUrl});

  final AccordUser user;
  final String? cdnUrl;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = accordAvatarUrl(user, cdnUrl);
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: accordAvatarColor(user, user.id),
        foregroundImage:
            avatarUrl == null ? null : CachedNetworkImageProvider(avatarUrl),
        child: Text(
          accordUserName(user, fallback: '?').characters.first.toUpperCase(),
          style: const TextStyle(fontSize: 11),
        ),
      ),
      title: Text(
        accordUserName(user, fallback: user.id),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

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
        ? data
            .map((e) => e is Map ? e['channel_id']?.toString() : e?.toString())
            .whereType<String>()
            .toSet()
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
