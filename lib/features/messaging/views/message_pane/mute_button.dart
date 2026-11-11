part of 'message_pane.dart';

/// A channel's notification state: the server-side mute from the shared
/// per-connection cache and the local notification level from app settings.
typedef _NotifState = ({
  String? activeKey,
  AsyncValue<Set<String>> mutedChannels,
  bool muted,
  String? level,
});

_NotifState _watchNotifState(WidgetRef ref, String channelId) {
  final activeKey = ref.watch(
    connectionsControllerProvider.select((state) => state.activeKey),
  );
  final mutedChannels = activeKey == null
      ? const AsyncData<Set<String>>(<String>{})
      : ref.watch(mutedChannelsControllerProvider(activeKey));
  return (
    activeKey: activeKey,
    mutedChannels: mutedChannels,
    muted: mutedChannels.value?.contains(channelId) ?? false,
    level: ref.watch(
      settingsControllerProvider.select(
        (settings) => activeKey == null
            ? null
            : settings.channelNotificationLevel(activeKey, channelId),
      ),
    ),
  );
}

String _notifLevelLabel(String? level) => level == null
    ? 'Mentions (default)'
    : level == AccordSettings.channelNotifAll
    ? 'All messages'
    : level == AccordSettings.channelNotifMentions
    ? 'Mentions only'
    : 'Nothing';

IconData _notifIcon(_NotifState state) => state.muted
    ? Icons.notifications_off
    : (state.level == AccordSettings.channelNotifNothing
          ? Icons.notifications_paused
          : (state.level == AccordSettings.channelNotifAll
                ? Icons.notifications_active
                : Icons.notifications_none));

void _applyNotifAction(
  BuildContext context,
  WidgetRef ref,
  _NotifState state,
  String channelId,
  _NotifAction action,
) {
  final activeKey = state.activeKey;
  if (activeKey == null) return;
  void setLevel(String? level) => ref
      .read(settingsControllerProvider.notifier)
      .setChannelNotificationLevel(activeKey, channelId, level);
  switch (action) {
    case _NotifAction.levelDefault:
      setLevel(null);
    case _NotifAction.levelAll:
      setLevel(AccordSettings.channelNotifAll);
    case _NotifAction.levelMentions:
      setLevel(AccordSettings.channelNotifMentions);
    case _NotifAction.levelNothing:
      setLevel(AccordSettings.channelNotifNothing);
    case _NotifAction.toggleMute:
      toggleChannelMute(
        context,
        ref,
        serverKey: activeKey,
        channelId: channelId,
        muted: state.muted,
      );
  }
}

/// The notification choices as labelled menu entries, for the compact header's
/// overflow sheet where the icon-only [_MuteButton] is not shown.
Future<void> _showNotificationMenu(
  BuildContext context,
  WidgetRef ref,
  _NotifState state,
  String channelId,
) {
  AccordMenuEntry level(String label, _NotifAction action, bool checked) =>
      AccordMenuEntry(
        label: label,
        icon: checked ? Icons.radio_button_checked : Icons.radio_button_off,
        onSelected: () =>
            _applyNotifAction(context, ref, state, channelId, action),
      );
  return showAccordContextMenu(
    context,
    title: 'Notifications',
    titleIcon: _notifIcon(state),
    entries: [
      level('Use default', _NotifAction.levelDefault, state.level == null),
      level(
        'All messages',
        _NotifAction.levelAll,
        state.level == AccordSettings.channelNotifAll,
      ),
      level(
        'Only @mentions',
        _NotifAction.levelMentions,
        state.level == AccordSettings.channelNotifMentions,
      ),
      level(
        'Nothing',
        _NotifAction.levelNothing,
        state.level == AccordSettings.channelNotifNothing,
      ),
      const AccordMenuEntry.divider(),
      AccordMenuEntry(
        label: state.muted ? 'Unmute' : 'Mute',
        icon: state.muted
            ? Icons.notifications_active_outlined
            : Icons.notifications_off_outlined,
        enabled: state.activeKey != null && !state.mutedChannels.isLoading,
        onSelected: () => _applyNotifAction(
          context,
          ref,
          state,
          channelId,
          _NotifAction.toggleMute,
        ),
      ),
    ],
  );
}

/// Notification controls for a channel. Server-side mutes come from the shared
/// per-connection cache; local notification levels remain app settings.
class _MuteButton extends ConsumerWidget {
  const _MuteButton({required this.channelId});

  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final state = _watchNotifState(ref, channelId);
    final level = state.level;

    return PopupMenuButton<_NotifAction>(
      tooltip: 'Notification settings — ${_notifLevelLabel(level)}',
      icon: Icon(_notifIcon(state), size: 18, color: colors.dirtyWhite),
      onSelected: (action) =>
          _applyNotifAction(context, ref, state, channelId, action),
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
          enabled: state.activeKey != null && !state.mutedChannels.isLoading,
          child: Text(state.muted ? 'Unmute channel' : 'Mute channel'),
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
