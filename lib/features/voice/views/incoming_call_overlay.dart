import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/features/channels/controllers/dm_channels.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/features/voice/controllers/call.dart';
import 'package:bonfire/features/voice/views/voice_view.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A banner that drops down from the top of the app while a DM call is ringing,
/// offering accept (audio) and decline. Accepting joins the call's voice channel
/// and opens the full-screen call view. Designed to be dropped into a [Stack]
/// (it returns a [Positioned]); renders nothing when no call is incoming.
class IncomingCallOverlay extends ConsumerWidget {
  const IncomingCallOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Surface transient call outcomes (e.g. "Call declined") app-wide. This
    // widget is always mounted in the home stack, so it's a stable host even
    // after the full-screen call view pops.
    ref.listen(callControllerProvider.select((s) => s.endedMessage),
        (prev, msg) {
      if (msg == null) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(msg)));
      ref.read(callControllerProvider.notifier).clearEndedMessage();
    });

    final incoming = ref.watch(callControllerProvider.select((s) => s.incoming));
    if (incoming == null) return const SizedBox.shrink();

    final colors = BonfireThemeExtension.of(context);
    // Backfill the caller's profile if it isn't cached yet.
    ref.read(accordUsersControllerProvider.notifier).ensure(incoming.callerId);
    final users = ref.watch(accordUsersControllerProvider);
    final cdnUrl = ref.watchCdnUrl();

    final caller = users[incoming.callerId];
    final callerName = accordUserName(caller, fallback: 'Someone');
    final avatarUrl = accordAvatarUrl(caller, cdnUrl);
    final bg = accordAvatarColor(caller, incoming.callerId);

    // For a group DM, name the group; otherwise it's a 1:1 call from the caller.
    final channels = ref.watch(dmChannelsControllerProvider);
    final channel =
        channels?.where((c) => c.id == incoming.channelId).firstOrNull;
    final isGroup =
        channel?.type == 'group_dm' || incoming.participants.length > 2;
    final subtitle = incoming.video ? 'Incoming video call' : 'Incoming call';
    final title = isGroup
        ? '${channel?.name?.isNotEmpty == true ? channel!.name : 'Group'} · $callerName'
        : callerName;

    final initial =
        callerName.isEmpty ? '?' : callerName.characters.first.toUpperCase();

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(12),
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colors.foreground,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black54, blurRadius: 16, offset: Offset(0, 4)),
              ],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: bg,
                  foregroundImage: avatarUrl == null
                      ? null
                      : CachedNetworkImageProvider(avatarUrl),
                  child: Text(initial,
                      style:
                          TextStyle(color: accordOnColor(bg), fontSize: 18)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall),
                      Text(subtitle,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall!
                              .copyWith(color: colors.gray)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _RoundButton(
                  color: colors.red,
                  icon: Icons.call_end,
                  tooltip: 'Decline',
                  onPressed: () => ref
                      .read(callControllerProvider.notifier)
                      .declineIncoming(),
                ),
                const SizedBox(width: 8),
                _RoundButton(
                  color: colors.green,
                  icon: incoming.video ? Icons.videocam : Icons.call,
                  tooltip: 'Accept',
                  onPressed: () => _accept(context, ref),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _accept(BuildContext context, WidgetRef ref) async {
    final incoming = ref.read(callControllerProvider).incoming;
    final navigator = Navigator.of(context, rootNavigator: true);
    final users = ref.read(accordUsersControllerProvider);
    final channels = ref.read(dmChannelsControllerProvider);
    final channel =
        channels?.where((c) => c.id == incoming?.channelId).firstOrNull;
    final isGroup = channel?.type == 'group_dm' ||
        (incoming?.participants.length ?? 0) > 2;
    final name = isGroup
        ? (channel?.name?.isNotEmpty == true ? channel!.name! : 'Group call')
        : accordUserName(users[incoming?.callerId], fallback: 'Call');

    final channelId =
        await ref.read(callControllerProvider.notifier).acceptIncoming();
    if (channelId == null || !navigator.mounted) return;
    await showFullScreenVoice(
      navigator.context,
      channelId: channelId,
      spaceId: null,
      channelName: name,
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.color,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final Color color;
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}
