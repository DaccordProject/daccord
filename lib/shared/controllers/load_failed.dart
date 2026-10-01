import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'load_failed.g.dart';

/// Whether a self-loading cache's initial REST fetch failed. Cache controllers
/// hold `null` for "no data", so this is the second bit: `null` + not failed =
/// loading, `null` + failed = show an error with Retry.
///
/// Keyed by [scope] (`members`, `messages`, `channels`, `spaces`), the owning
/// connection's [serverKey], and the space/channel [id] (empty for
/// connection-wide caches). Watch it through each feature's named helper
/// (`membersLoadFailedProvider`, …), not directly.
@Riverpod(keepAlive: true)
class LoadFailed extends _$LoadFailed {
  @override
  bool build(String scope, String serverKey, String id) => false;

  // ignore: use_setters_to_change_properties
  void set(bool value) => state = value;
}
