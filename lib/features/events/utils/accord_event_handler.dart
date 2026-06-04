import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/events/controllers/connection.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
import 'package:bonfire/features/spaces/controllers/space.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Subscribes a freshly-built [AccordClient]'s gateway streams to Riverpod
/// state. The Accord analogue of `handleEvents` in `event_handler.dart`.
///
/// Where Bonfire listened to firebridge's cache/gateway streams, this listens
/// to accordkit's typed gateway streams and routes them into the Accord
/// controllers. Returns a disposer that cancels every subscription — call it
/// before tearing down the client (e.g. on logout / reconnect).
VoidCallback handleAccordEvents(Ref ref, AccordClient client) {
  final subs = <StreamSubscription<dynamic>>[];

  void setConnection(ConnectionStatus status) =>
      ref.read(connectionControllerProvider.notifier).set(status);

  // ── Connection lifecycle ─────────────────────────────────────────────────
  subs.add(client.onConnected.listen((_) {
    setConnection(ConnectionStatus.connected);
  }));
  subs.add(client.onReconnecting.listen((_) {
    setConnection(ConnectionStatus.reconnecting);
  }));
  subs.add(client.onDisconnected.listen((info) {
    debugPrint('Accord gateway disconnected: ${info.code} ${info.reason}');
    setConnection(ConnectionStatus.disconnected);
  }));

  // ── Initial sync ─────────────────────────────────────────────────────────
  subs.add(client.onReady.listen((_) async {
    setConnection(ConnectionStatus.ready);
    await _loadSpaces(ref, client);
  }));

  // ── Space cache ──────────────────────────────────────────────────────────
  void cacheSpace(AccordSpace space) {
    ref.read(spacesControllerProvider.notifier).upsertSpace(space);
    ref.read(spaceControllerProvider(space.id).notifier).setSpace(space);
  }

  subs.add(client.onSpaceCreate.listen(cacheSpace));
  subs.add(client.onSpaceUpdate.listen(cacheSpace));
  subs.add(client.onSpaceDelete.listen((data) {
    final id = data['id']?.toString() ?? data['space_id']?.toString();
    if (id != null) {
      ref.read(spacesControllerProvider.notifier).removeSpace(id);
    }
  }));

  // ── Channel cache (per space) ────────────────────────────────────────────
  void cacheChannel(AccordChannel channel) {
    final spaceId = channel.spaceId;
    if (spaceId == null) return;
    ref
        .read(accordChannelsControllerProvider(spaceId).notifier)
        .upsertChannel(channel);
  }

  subs.add(client.onChannelCreate.listen(cacheChannel));
  subs.add(client.onChannelUpdate.listen(cacheChannel));
  subs.add(client.onChannelDelete.listen((channel) {
    final spaceId = channel.spaceId;
    if (spaceId == null) return;
    ref
        .read(accordChannelsControllerProvider(spaceId).notifier)
        .removeChannel(channel.id);
  }));

  // ── Message cache (per channel) ──────────────────────────────────────────
  // Only touch channels the UI has actually opened (see [activeMessageChannels])
  // so we don't history-load every channel that receives a message.
  subs.add(client.onMessageCreate.listen((message) {
    if (!activeMessageChannels.contains(message.channelId)) return;
    ref
        .read(accordMessagesControllerProvider(message.channelId).notifier)
        .addMessage(message);
  }));
  subs.add(client.onMessageUpdate.listen((message) {
    if (!activeMessageChannels.contains(message.channelId)) return;
    ref
        .read(accordMessagesControllerProvider(message.channelId).notifier)
        .updateMessage(message);
  }));
  subs.add(client.onMessageDelete.listen((data) {
    final channelId = data['channel_id']?.toString();
    final messageId =
        data['id']?.toString() ?? data['message_id']?.toString();
    if (channelId == null || messageId == null) return;
    if (!activeMessageChannels.contains(channelId)) return;
    ref
        .read(accordMessagesControllerProvider(channelId).notifier)
        .removeMessage(messageId);
  }));

  return () {
    for (final sub in subs) {
      sub.cancel();
    }
  };
}

/// Fetches the user's spaces over REST and seeds the rail + per-space caches.
Future<void> _loadSpaces(Ref ref, AccordClient client) async {
  final result = await client.users.listSpaces();
  if (!result.ok) {
    debugPrint('Failed to load spaces: ${result.error}');
    return;
  }
  final data = result.data;
  if (data is! List) return;

  final spaces = data.whereType<AccordSpace>().toList();
  ref.read(spacesControllerProvider.notifier).setSpaces(spaces);
  for (final space in spaces) {
    ref.read(spaceControllerProvider(space.id).notifier).setSpace(space);
  }
}
