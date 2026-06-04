import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'accord_messages.g.dart';

/// Channels that currently have a live message controller. The gateway handler
/// consults this so it only mutates caches the UI has actually opened, rather
/// than instantiating (and history-loading) a controller for every channel
/// that happens to receive a message.
final Set<String> activeMessageChannels = <String>{};

/// A channel's recent message history, keyed by channel ID, ordered
/// oldest→newest for display. Self-loads via `messages.list` the first time
/// it's watched (once logged in) and is kept in sync by message
/// create/update/delete gateway events. `null` means "not loaded yet".
@Riverpod(keepAlive: true)
class AccordMessagesController extends _$AccordMessagesController {
  @override
  List<AccordMessage>? build(String channelId) {
    activeMessageChannels.add(channelId);
    ref.onDispose(() => activeMessageChannels.remove(channelId));

    final client = ref.watch(
      accordAuthProvider
          .select((s) => s is AccordAuthLoggedIn ? s.client : null),
    );
    if (client != null) {
      _load(client, channelId);
    }
    return null;
  }

  Future<void> _load(AccordClient client, String channelId) async {
    final result = await client.messages.list(channelId, query: {'limit': 50});
    if (!result.ok) {
      debugPrint('Failed to load messages for $channelId: ${result.error}');
      return;
    }
    final data = result.data;
    if (data is List) {
      // The REST list returns newest-first; store oldest-first for display.
      state = data.whereType<AccordMessage>().toList().reversed.toList();
    }
  }

  /// Appends a newly-received message, ignoring duplicates (e.g. the gateway
  /// echo of a message we just sent).
  void addMessage(AccordMessage message) {
    final current = [...(state ?? const <AccordMessage>[])];
    if (current.any((m) => m.id == message.id)) return;
    current.add(message);
    state = current;
  }

  void updateMessage(AccordMessage message) {
    final current = state;
    if (current == null) return;
    final index = current.indexWhere((m) => m.id == message.id);
    if (index < 0) return;
    final copy = [...current];
    copy[index] = message;
    state = copy;
  }

  void removeMessage(String messageId) {
    final current = state;
    if (current == null) return;
    state = current.where((m) => m.id != messageId).toList();
  }
}
