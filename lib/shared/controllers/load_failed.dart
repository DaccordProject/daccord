import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'load_failed.g.dart';

/// Whether a self-loading cache's initial REST fetch failed (a non-2xx
/// response, a network error, or a timeout).
///
/// The cache controllers hold `null` for "no data", which on its own cannot
/// tell a pane still loading apart from one whose load failed — so a failed
/// fetch used to render as a permanent spinner. This flag is the second bit:
/// `null` + not failed = loading, `null` + failed = show an error with a Retry.
///
/// Written by the controller that owns the fetch (cleared on success, set once
/// its retries are exhausted) and by a pane's Retry button before it
/// re-triggers the load. Keyed by [scope] (which cache: `members`, `messages`,
/// `channels`, `spaces`), the owning connection's [serverKey], and the [id]
/// within it (the space or channel; empty for connection-wide caches).
///
/// Don't watch this provider directly — each feature exposes a named helper
/// (`membersLoadFailedProvider`, `channelsLoadFailedProvider`, …) that fills in
/// its own scope.
@Riverpod(keepAlive: true)
class LoadFailed extends _$LoadFailed {
  @override
  bool build(String scope, String serverKey, String id) => false;

  // ignore: use_setters_to_change_properties
  void set(bool value) => state = value;
}
