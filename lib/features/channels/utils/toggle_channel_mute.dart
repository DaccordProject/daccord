import 'package:bonfire/features/channels/controllers/muted_channels.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Flips [channelId]'s server-side mute and reports a rejection to the user.
///
/// The controller updates optimistically and rolls back when the server says
/// no; without this the switch just sprang back with no explanation (#306).
/// Shared by the channel header's notification menu and the channel context
/// menu so both say the same thing. [MuteResult.busy] is deliberately silent —
/// the request that is still in flight owns the outcome.
Future<void> toggleChannelMute(
  BuildContext context,
  WidgetRef ref, {
  required String serverKey,
  required String channelId,
  required bool muted,
}) async {
  final result = await ref
      .read(mutedChannelsControllerProvider(serverKey).notifier)
      .setMuted(channelId, !muted);
  if (result != MuteResult.failed || !context.mounted) return;
  showInfoSnack(
    context,
    muted ? 'Failed to unmute channel' : 'Failed to mute channel',
  );
}
