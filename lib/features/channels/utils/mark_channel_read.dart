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
/// The acked position is the newest cached message, falling back to
/// [fallbackMessageId] (the channel's `last_message_id`) when the message cache
/// is empty — which is the common case for a channel whose messages were never
/// opened (any voice channel joined without its chat panel) and for a *phantom*
/// unread whose message has since been deleted.
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
  ref.read(readStateControllerProvider(key).notifier).markRead(channelId);

  final messages = ref.read(accordMessagesControllerProvider(key, channelId));
  final lastId = messages?.isNotEmpty == true
      ? messages!.last.id
      : fallbackMessageId;
  if (lastId == null) return;
  ref
      .read(accordAuthProvider.notifier)
      .clientForKey(key)
      ?.channels
      .ack(channelId, lastId);
}
