import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'accord_channels.g.dart';

/// A space's channel list, keyed by space ID. The Accord analogue of Bonfire's
/// firebridge-backed channel list. Self-loads via `spaces.listChannels` the
/// first time it's watched (once logged in) and is kept in sync by
/// channel create/update/delete gateway events. `null` means "not loaded yet".
@Riverpod(keepAlive: true)
class AccordChannelsController extends _$AccordChannelsController {
  @override
  List<AccordChannel>? build(String spaceId) {
    final client = ref.watch(
      accordAuthProvider
          .select((s) => s is AccordAuthLoggedIn ? s.client : null),
    );
    if (client != null) {
      _load(client, spaceId);
    }
    return null;
  }

  Future<void> _load(AccordClient client, String spaceId) async {
    final result = await client.spaces.listChannels(spaceId);
    if (!result.ok) {
      debugPrint('Failed to load channels for $spaceId: ${result.error}');
      return;
    }
    final data = result.data;
    if (data is List) {
      state = _sorted(data.whereType<AccordChannel>().toList());
    }
  }

  void setChannels(List<AccordChannel> channels) =>
      state = _sorted(channels);

  /// Inserts [channel], or replaces it in place if already present.
  void upsertChannel(AccordChannel channel) {
    final current = [...(state ?? const <AccordChannel>[])];
    final index = current.indexWhere((c) => c.id == channel.id);
    if (index >= 0) {
      current[index] = channel;
    } else {
      current.add(channel);
    }
    state = _sorted(current);
  }

  void removeChannel(String channelId) {
    final current = state;
    if (current == null) return;
    state = current.where((c) => c.id != channelId).toList();
  }

  /// Orders channels by `position` (categories carry their children via
  /// `parentId`, which the UI groups separately), falling back to ID.
  List<AccordChannel> _sorted(List<AccordChannel> channels) {
    final copy = [...channels];
    copy.sort((a, b) {
      final pa = _asInt(a.position);
      final pb = _asInt(b.position);
      if (pa != pb) return pa.compareTo(pb);
      return a.id.compareTo(b.id);
    });
    return copy;
  }

  int _asInt(Object? v) => v is int ? v : int.tryParse('$v') ?? 0;
}
