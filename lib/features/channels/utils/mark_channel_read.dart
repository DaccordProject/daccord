import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/channels/controllers/read_state.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Clears [channelId]'s unread badge locally *and* POSTs `channels.ack` so the
/// server's read position catches up too.
///
/// Both halves matter: the local clear hides the dot now, the ack is what stops
/// the READY payload's `unread` array from re-lighting it on the next connect.
/// The acked position is the newest of the cached history, gateway/READY
/// position, and [fallbackMessageId] (the channel's `last_message_id`). Cached
/// history may be stale after switching tabs or reconnecting, so it must never
/// take precedence over a newer known position.
///
/// [serverKey] pins the ack to a specific connection; it defaults to the active
/// one. Pass it explicitly when the channel may live on a background server
/// (e.g. a voice call pinned to a server the user has since navigated away
/// from).
void markChannelRead(
  WidgetRef ref,
  String channelId, {
  String? serverKey,
  String? fallbackMessageId,
}) {
  final key = serverKey ?? ref.read(connectionsControllerProvider).activeKey;
  if (key == null) return;
  final tracker = ref.read(readStateControllerProvider(key).notifier);
  final messages = ref.read(accordMessagesControllerProvider(key, channelId));
  final candidates = <String>[
    if (messages?.isNotEmpty == true) messages!.last.id,
    if (fallbackMessageId != null) fallbackMessageId,
    if (tracker.latestMessageId(channelId) case final id?) id,
  ]..removeWhere((id) => id.isEmpty);
  candidates.sort(compareMessageIds);
  tracker.acknowledge(
    ref.read(accordAuthProvider.notifier).clientForKey(key),
    channelId,
    candidates.lastOrNull,
  );
}
