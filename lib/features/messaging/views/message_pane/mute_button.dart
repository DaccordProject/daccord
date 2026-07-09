part of 'message_pane.dart';

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

  AccordClient? get _client => ref.accordClient;

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
